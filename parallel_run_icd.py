import torch
import torch.nn as nn
import torch.nn.functional as F
import pandas as pd
import numpy as np
import gc
from transformers import AutoTokenizer, AutoModel, AdamW, get_linear_schedule_with_warmup, set_seed
from sklearn.metrics import f1_score, accuracy_score
from torch.utils.data import Dataset
from torch.utils.data.dataloader import DataLoader
from tqdm import tqdm
from evaluation import all_metrics

import torch.multiprocessing as mp
from torch.utils.data.distributed import DistributedSampler
from torch.nn.parallel import DistributedDataParallel as DDP
from torch.distributed import init_process_group, destroy_process_group
import os
import argparse

class CustomDataset(Dataset):
    def __init__(self, inputs, outputs):
        self.inputs = inputs
        self.outputs = outputs
        
    def __len__(self):
        return len(self.inputs)
    
    def __getitem__(self, idx):
        input = self.inputs[idx]
        output = self.outputs[idx]
        return input, output

# **1. Main Model Definition (BERT + LabelAttention + Loss)**


class ICD9_Detection(nn.Module):
    def __init__(self, num_labels):
        super(ICD9_Detection, self).__init__()
        self.bert = AutoModel.from_pretrained("emilyalsentzer/Bio_Discharge_Summary_BERT")
        self.dropout = nn.Dropout(0.1)
        self.linear_z = nn.Linear(768, 768)
        self.linear_a = nn.Linear(768, num_labels)
        self.linear_o = nn.Linear(768, num_labels)
        self.num_labels = num_labels

    def forward(self, input_ids, attention_mask, token_type_ids):
        outputs = self.bert(input_ids.view(-1, 128), attention_mask=attention_mask.view(-1, 128), token_type_ids=token_type_ids.view(-1, 128))
        last_hidden_state = outputs[0].view(input_ids.shape[0],input_ids.shape[1]*input_ids.shape[2], 768) ##shape: (b, s*c, 768)
        z = torch.tanh(self.linear_z(last_hidden_state)) ##shape: (b, s*c, 768)
        a = torch.softmax(self.linear_a(z), dim=1).transpose(1,2) ##shape: (b, num_labels, s*c) weights for each label
        d = torch.matmul(a, last_hidden_state) ##shape: (b, num_labels, 768) weighted sum for each label (check matmul once again)
        logits = self.linear_o.weight.mul(d).sum(dim=2) ##shape: (num_labels) logits for each label
        return logits
    


def ddp_setup(rank, world_size):
    """
    Args:
        rank: Unique identifier of each process
        world_size: Total number of processes
    """
    os.environ["MASTER_ADDR"] = "localhost"
    os.environ["MASTER_PORT"] = "12355"
    init_process_group(backend="nccl", rank=rank, world_size=world_size)
    
def batch_convertor(training_data, training_labels, batch_size = 32):##add padding when # sentences differes across batches
    all_batches_sentences, all_batches_attention, all_batches_tokentype = [], [], []
    all_batches_labels = []
    for i in range(0, len(training_data), batch_size):
        batch = training_data[i:i+batch_size]
        max_num_sentences = max([len(x[0]) for x in batch])
        batch_sentences, batch_attention_masks, batch_token_type_ids = [], [], []
        for j in range(len(batch)):
            num_sentences = len(batch[j][0])
            batch_sentences.append(batch[j][0] + [[0]*128]*(max_num_sentences - num_sentences))
            batch_attention_masks.append(batch[j][1] + [[0]*128]*(max_num_sentences - num_sentences))
            batch_token_type_ids.append(batch[j][2] + [[0]*128]*(max_num_sentences - num_sentences))

        all_batches_sentences.append(torch.tensor(batch_sentences))
        all_batches_attention.append(torch.tensor(batch_attention_masks))
        all_batches_tokentype.append(torch.tensor(batch_token_type_ids))
        all_batches_labels.append(torch.tensor(training_labels[i:i+batch_size]))
    
    return [all_batches_sentences, all_batches_attention,all_batches_tokentype], all_batches_labels


def split_text_to_sentences(text, tokenizer,max_length = 128, padding = False, token_length = 3072 ):
    text = text.replace('"', '') ## to remove quotes at the beginning and end of the text
    #text = text.split(' ') ## to split the text into words
    encoded_dict = tokenizer(text, padding=padding, truncation=True, max_length=token_length, add_special_tokens=True)
    input_ids = encoded_dict['input_ids']
    sentences = []
    attention_masks = []
    token_type_ids = []
    for i in range(0, len(input_ids), max_length):
        sentences.append(input_ids[i:i+max_length]) ## last sentence may be less than max_length
        attention_masks.append(encoded_dict['attention_mask'][i:i+max_length])
        token_type_ids.append(encoded_dict['token_type_ids'][i:i+max_length])
        if len(sentences[-1]) < max_length: ## if last sentence is less than max_length, pad it with [PAD]
            # tl =len(sentences[-1][0]) ## length of token IDs generated by tokenizer
            # sentences[-1] = sentences[-1] + [[0]*tl]*(max_length - len(sentences[-1])) ## pad with 0
            # attention_masks[-1] = attention_masks[-1] + [[0]*tl]*(max_length - len(attention_masks[-1])) ## pad with 0
            # token_type_ids[-1] = token_type_ids[-1] + [[0]*tl]*(max_length - len(token_type_ids[-1])) ## pad with 0

            sentences[-1] = sentences[-1] + [0]*(max_length - len(sentences[-1])) ## pad with 0
            attention_masks[-1] = attention_masks[-1] + [0]*(max_length - len(attention_masks[-1])) ## pad with 0
            token_type_ids[-1] = token_type_ids[-1] + [0]*(max_length - len(token_type_ids[-1])) ## pad with 0

    return [sentences, attention_masks, token_type_ids]

def labels_to_one_hot(labels, all_labels):
    one_hot_labels = []
    for label in labels:
        one_hot = [0]*len(all_labels)
        for code in label:
            one_hot[all_labels.index(code)] = 1
        one_hot_labels.append(one_hot)
    return one_hot_labels
    



def data_pull(df, all_labels, padding_tokentization, max_length_tokenization ):
    string_labels = df['label'].apply(lambda x: type(x) == str)
    df = df[string_labels]
    tokenizer = AutoTokenizer.from_pretrained("emilyalsentzer/Bio_Discharge_Summary_BERT", use_fast=True)
    notes = df['text'].apply(lambda x: split_text_to_sentences(x, tokenizer, 128,padding_tokentization, max_length_tokenization)) #list of list of sentences
    labels = df['label'].apply(lambda x: x.split(';')) ##list of ICD9 codes
    notes = notes.values.tolist() ## convert to list
    labels = labels.values.tolist() ## convert to list
    one_hot_labels = labels_to_one_hot(labels, all_labels)

    return notes, one_hot_labels

def batch_collator(inputs):
    batch = dict()
    max_num_sentences = max([len(x[0][0]) for x in inputs])

    batch_sentences, batch_attention_masks, batch_token_type_ids, batch_labels = [], [], [], []   
    for j in range(len(inputs)):
        num_sentences = len(inputs[j][0][0])
        batch_sentences.append(inputs[j][0][0] + [[0]*128]*(max_num_sentences - num_sentences))
        batch_attention_masks.append(inputs[j][0][1] + [[0]*128]*(max_num_sentences - num_sentences))
        batch_token_type_ids.append(inputs[j][0][2] + [[0]*128]*(max_num_sentences - num_sentences))
        batch_labels.append(inputs[j][1])

    batch["input_ids"] = torch.tensor(batch_sentences)
    batch["attention_mask"] = torch.tensor(batch_attention_masks)
    batch["token_type_ids"] = torch.tensor(batch_token_type_ids)
    batch["labels"] = torch.tensor(batch_labels)
    
    return batch



def custom_loss(y_true, y_logit, Wp, Wn):
    '''
    Multi-label cross-entropy
    * Required "Wp", "Wn" as positive & negative class-weights
    y_true: true value
    y_logit: predicted value
    '''
    loss = float(0)
    
    for i, key in enumerate(Wp.keys()):
        first_term = Wp[key] * y_true[i] * K.log(y_logit[i] + K.epsilon())
        second_term = Wn[key] * (1 - y_true[i]) * K.log(1 - y_logit[i] + K.epsilon())
        loss -= (first_term + second_term)
    return loss

## training by taking one example at a time
def train(model,train_dataloader, dev_dataloader, num_epochs, optimizer, rank, model_save_path = None, threshold=0.3):
    if rank == 0:
        best_dev_micro_f1, best_dev_macro_f1 = evaluate_model(model, dev_dataloader, rank,threshold=threshold)
    print(f"Training Started at : [GPU{rank}]")
    for epoch in range(num_epochs):
        epoch_loss = []
        #model.train()
        for step, batch in tqdm(enumerate(train_dataloader), total=len(train_dataloader)):
            #print("Start: ",torch.cuda.memory_allocated(device=rank))
            optimizer.zero_grad()
            note = batch['input_ids'].to(rank)
            attention_mask = batch['attention_mask'].to(rank)
            token_type_ids = batch['token_type_ids'].to(rank)
            label = batch['labels'].to(rank)
            logits = model(note, attention_mask, token_type_ids)

            loss = nn.BCEWithLogitsLoss()
            loss = loss(logits.view(-1, model.module.num_labels), label.float().view(-1, model.module.num_labels))
            loss.backward()
            optimizer.step()
            del note, attention_mask, token_type_ids, label
            if step%5000 == 0 and rank==0:
                model.eval()
                dev_micro_f1, dev_macro_f1 = evaluate_model(model, dev_dataloader, rank,threshold=threshold)
                print('GPU: {}, Epoch: {}, #Batches: {}, Loss: {}, Dev Micro F1: {}, Dev Macro F1: {}'.format(rank, epoch, step, loss.item(), dev_micro_f1, dev_macro_f1))

            epoch_loss.append(loss.item())
            del loss
            torch.cuda.empty_cache() 
            #print("End: ",torch.cuda.memory_allocated(device=rank))
            
        print('Epoch: {}, Loss: {}'.format(epoch, np.mean(epoch_loss)))
        if rank==0:
            ###save model            
            final_save_path = model_save_path + str(epoch) + '.pt'
            ckp = model.module.state_dict()
            torch.save(ckp, final_save_path)
            print('Model saved to {}'.format(final_save_path))
            dev_micro_f1, dev_macro_f1 = evaluate_model(model, dev_dataloader, rank,threshold=threshold)
            if dev_macro_f1>best_dev_macro_f1 or dev_micro_f1>best_dev_micro_f1:
                best_dev_macro_f1 = dev_macro_f1
                best_dev_micro_f1 = dev_micro_f1
                best_model_path = 'parallel_saved_models/best_model.pt' 
                torch.save(ckp, best_model_path)
                print('Best model updated',dev_macro_f1,dev_micro_f1)


def evaluate_model (model, dev_dataloader, rank, threshold=0.3):
    #model.eval()
    with torch.no_grad():
        predictions = []
        actual = []
        for step,batch in enumerate(dev_dataloader):
            note = batch['input_ids'].to(rank)
            attention_mask = batch['attention_mask'].to(rank)
            token_type_ids = batch['token_type_ids'].to(rank)
            logits = model(note, attention_mask, token_type_ids)
            actual_batch = batch['labels'].to(rank)
            for ll in range(len(logits)):#for each example in the batch
                logits_i = torch.sigmoid(logits[ll])
                logits_i = [1 if x>threshold else 0 for x in logits_i]
                predictions.append(logits_i) ## appending for each example in the batch/dataset
                actual.append(actual_batch[ll])
    

    actual = [ x.tolist() for x in actual ]
    ##f1_score calc
    metrics = all_metrics(yhat=torch.tensor(predictions).numpy(), y=torch.tensor(actual).numpy())
    #micro_f1 = f1_score(actual.numpy(), predictions.numpy(), average='micro',zero_division=1)
    #macro_f1 = f1_score(actual.numpy(), predictions.numpy(), average='macro',zero_division=1)

    #print('Micro F1: {}, Macro F1: {}'.format(micro_f1, macro_f1))

    #return micro_f1, macro_f1
    return metrics["f1_micro"],metrics["f1_macro"] 

def main(rank: int, world_size: int, total_epochs: int, batch_size: int, mode):
    ddp_setup(rank, world_size)
    torch.cuda.set_per_process_memory_fraction(0.75, device=rank)
    ###key hyperparameters
    max_length_tokenization = 3072 ## max length of token IDs (for each word)
    padding_tokentization = True ## whether to pad the token IDs
    set_seed(143)
    # **0. Load Input data, split the text to sentences for BERT & Tokenize to IDs, onehot encoding of lables**


    ##get all labels (top 50 as of now)
    all_labels = pd.read_csv('../data/parallel/all_codes.txt', header=None)
    all_labels.columns = ["ICD9_CODE"]
    all_labels = all_labels['ICD9_CODE'].tolist()

    train_df = pd.read_csv('../data/mimic3/train_notes_pv1_full.csv')
    #train_df = pd.read_csv('../data/parallel/train_notes_pv1_full.csv')
    train_notes, train_labels = data_pull(train_df, all_labels,padding_tokentization, max_length_tokenization)

    train_dataset = CustomDataset(train_notes,train_labels)
    train_dataloader = DataLoader(train_dataset,shuffle = False, collate_fn=batch_collator, 
                                  batch_size=batch_size,sampler=DistributedSampler(train_dataset))
    dev_df = pd.read_csv('../data/mimic3/dev_notes_pv1_full.csv')
    #dev_df = pd.read_csv('../data/parallel/dev_notes_pv1_full.csv')
    #TAKE one in 6 rows
    #dev_df = dev_df[:5000]
    #dev_df = dev_df.iloc[::6, :]
    dev_notes, dev_labels = data_pull(dev_df, all_labels,padding_tokentization, max_length_tokenization)
    dev_dataset = CustomDataset(dev_notes,dev_labels)
    dev_dataloader = DataLoader(dev_dataset, collate_fn=batch_collator, batch_size=2)

    ##clearning memory

    gc.collect()
    del train_df
    del dev_df
 

    model_save_path = 'parallel_saved_models/SH_ICD9_detection_model_epoch_'
    best_model_path = 'parallel_saved_models/best_model.pt' 
    model = ICD9_Detection(len(all_labels)).to(rank)
    #load the latest model file if found
    if os.path.isfile(best_model_path):
       model.load_state_dict(torch.load(best_model_path))
    
    model = DDP(model, device_ids=[rank],find_unused_parameters=True)

    optimizer = torch.optim.Adam(model.parameters(), lr=1e-5)
    if(mode == 'train'):
        train(model, train_dataloader, dev_dataloader, total_epochs, optimizer, rank , model_save_path=model_save_path, threshold=0.3)
    if rank ==0:
        best_micro_f1=0
        best_macro_f1 = 0
        best_threshold = -1
        for i in [0.15, 0.35, 0.25,0.2,0.3]:
            micro_f1, macro_f1 = evaluate_model(model, dev_dataloader, rank, threshold=i)
            print("for threshold ", i, "micro_f1: ", micro_f1, "macro_f1: ", macro_f1)
            #if(best_macro_f1<macro_f1 or best_micro_f1< micro_f1):
            if(best_macro_f1<macro_f1):
                best_micro_f1 = micro_f1
                best_macro_f1 = macro_f1
                best_threshold = i
            #evaluate_model(model, dev_dataloader, rank, threshold=0.2)


        # Testing 
        print("Testing: ")
        test_df = pd.read_csv('../data/mimic3/test_notes_pv1_full.csv')
        test_notes, test_labels = data_pull(test_df, all_labels,padding_tokentization, max_length_tokenization)
        test_dataset = CustomDataset(test_notes,test_labels)
        test_dataloader = DataLoader(test_dataset,shuffle = False, collate_fn=batch_collator, 
                                  batch_size=batch_size,sampler=DistributedSampler(test_dataset))
        micro_f1, macro_f1 = evaluate_model(model, test_dataloader, rank, threshold=best_threshold)
        print("for threshold ", best_threshold, "micro_f1: ", micro_f1, "macro_f1: ", macro_f1)

    destroy_process_group()


if __name__ == "__main__":
    #os.environ['PYTORCH_CUDA_ALLOC_CONF'] = '4096'
    parser = argparse.ArgumentParser(description='simple distributed training job')
    parser.add_argument('total_epochs',default = 4, type=int, help='Total epochs to train the model')
    parser.add_argument('batch_size', default=4, type=int, help='Input batch size on each device (default: 4)')
    parser.add_argument('mode', default='train', type=str, help='train mode by default')
    args = parser.parse_args()

    if torch.cuda.is_available():
        device = torch.device("cuda")
        print('GPU device is available')
    else:
        device = torch.device("cpu")
        print('GPU device is not available, using CPU instead')
    world_size = torch.cuda.device_count()
    print('World size: ', world_size)
    mp.spawn(main, args=(world_size, args.total_epochs, args.batch_size, args.mode), nprocs=world_size)