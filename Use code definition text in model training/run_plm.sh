cd PLM-ICD-master/src
allcode="../data/mimic3/ALL_CODES.txt"
codeDesc="../../caml-mimic-master/mimicdata/mimic3/code_desc.csv"
train="../../caml-mimic-master/mimicdata/mimic3/train_full.csv"
dev="../../caml-mimic-master/mimicdata/mimic3/dev_full.csv" 
test="../../caml-mimic-master/mimicdata/mimic3/test_full.csv"  
model="../models/RoBERTa-base-PM-M3-Voc"
out="../models/roberta-mimic3-full"

##pretrain model
accelerate launch --multi_gpu --num_processes=8 run_icd.py \
    --train_file ${codeDesc} \
    --validation_file ${codeDesc} \
    --code_file ${allcode} \
    --max_length 3072 \
    --chunk_size 128 \
    --model_name_or_path ${model} \
    --per_device_train_batch_size 1 \
    --gradient_accumulation_steps 1 \
    --per_device_eval_batch_size 1 \
    --num_train_epochs 20 \
    --num_warmup_steps 2000 \
    --output_dir ${out} \
    --model_type roberta \
    --model_mode laat
 
cp ${model}/merges.txt ${out}
cp ${model}/vocab.json ${out}


### train model
accelerate launch --multi_gpu --num_processes=8 run_icd.py \
    --train_file  ${train}\
    --validation_file ${dev} \
    --max_length 3072 \
    --chunk_size 128 \
    --model_name_or_path ${out} \
    --per_device_train_batch_size 1 \
    --gradient_accumulation_steps 1 \
    --per_device_eval_batch_size 1 \
    --num_train_epochs 20 \
    --num_warmup_steps 2000 \
    --output_dir ${out} \
    --model_type roberta \
    --model_mode laat


python3 run_icd.py \
    --train_file ${dev} \
    --validation_file ${dev} \
    --max_length 3072 \
    --chunk_size 128 \
    --model_name_or_path ${out} \
    --per_device_eval_batch_size 1 \
    --num_train_epochs 0 \
    --output_dir ${out} \
    --model_type roberta \
    --model_mode laat  
    

python3 run_icd.py \
    --train_file ${test} \
    --validation_file ${test} \
    --max_length 3072 \
    --chunk_size 128 \
    --model_name_or_path ${out} \
    --per_device_eval_batch_size 1 \
    --num_train_epochs 0 \
    --output_dir ${out} \
    --model_type roberta \
    --model_mode laat    
