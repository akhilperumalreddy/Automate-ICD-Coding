setwd("~/Google Drive (shaun.the.customer@gmail.com)/UWM Courses/CS 769 NLP/assignment3/ICD_phecode_mapping")

load("code_descriptions.RData")
temp=subset(codeDescription,CODE_TYPE != "CPT")
temp=temp[order(temp$CODE),]
write.table(temp,file = "ICD_code_definitions.txt", row.names = F)

load("ICD_phecode_map_processed.RData")
temp = sub("\\.","", ICDGroup$ICD)
ICDGroup=cbind(ICD_nodot = temp, ICDGroup)
names(ICDGroup)[3] = "CODE_TYPE"
names(ICDGroup)[5] = "phecode_d1"
write.table(ICDGroup, file = "ICD_phecode_map.txt", row.names = F)

load("phecode_descriptions.RData")
write.table(phecode_definitions, file = "phecode_definitions1.2.txt", row.names = F)
