# Automate-ICD-Coding
Automate ICD coding based on discharge summary using Pretrained Language models. This is as part of NLP 769 course group project. 

## Model Overview

In this project, we present our implementation of a transformer-based model for automatic generation of ICD (International Classification of Diseases) codes using discharge summaries [1]. The model addresses three key challenges faced by existing methods, including a large label space, long input sequences, and domain mismatch between pretraining and fine-tuning. We conducted experiments on the MIMIC (Medical Information Mart for Intensive Care) dataset and achieved similar performance in terms of multiple metrics. Additionally, we explored several variations to this model, including further pretraining using ICD code descriptions in code dictionaries and laveraging the hierarchical taxonomy of ICD codes to improve the code automation accuracy. Our findings demonstrate the effectiveness of leveraging pre-trained language models for automatic ICD coding and offer insights for future research in this area. For details, please referer to our [presentation slides](https://github.com/akhilperumalreddy/Automate-ICD-Coding/blob/main/Presentation_slides.pdf).

[1] *Huang, C. W., Tsai, S. C., & Chen, Y. N. (2022, July). PLM-ICD: Automatic ICD Coding with Pretrained Language Models. In Proceedings of the 4th Clinical Natural Language Processing Workshop (pp. 10-20)*.
