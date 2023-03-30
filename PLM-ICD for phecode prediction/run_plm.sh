cd PLM-ICD-master/src
epoch='20'
allcode="../data/mimic3/ALL_PHE_CODES.txt"
train='../data/mimic3/train_ds_full_w_phe.csv'
dev='../data/mimic3/dev_ds_full_w_phe.csv'
test="../data/mimic3/test_ds_notes_full.csv"
type="icd"


## train model
## python3 run_icd.py 
accelerate launch --multi_gpu --num_processes=2 run_icd.py \
    --train_file ${train} \
    --validation_file ${dev} \
    --code_file ${allcode} \
    --max_length 3072 \
    --chunk_size 128 \
    --model_name_or_path ../models/RoBERTa-base-PM-M3-Voc-distill-align-hf \
    --per_device_train_batch_size 1 \
    --gradient_accumulation_steps 8 \
    --per_device_eval_batch_size 1 \
    --num_train_epochs ${epoch} \
    --num_warmup_steps 2000 \
    --output_dir ../models/roberta-mimic3-${type}-full-${epoch} \
    --model_type roberta \
    --model_mode laat

: '
## evaluate model
python3 run_icd.py \
    --train_file ${train} \
    --validation_file ${test} \
    --code_file ${allcode} \
    --max_length 3072 \
    --chunk_size 128 \
    --model_name_or_path ../models/roberta-mimic3-${type}-full-${epoch} \
    --per_device_eval_batch_size 1 \
    --num_train_epochs 0 \
    --output_dir ../models/roberta-mimic3-${type}-full-${epoch} \
    --model_type roberta \
    --model_mode laat
'    
