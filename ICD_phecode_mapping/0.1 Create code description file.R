setwd("~/Desktop/Xianshi Code 2nd round")

###########################################CODE DESCRIPTIONS
library(reshape2)

CPT_table <- read.delim("Auxiliary external files--Code Descriptions/CPT_conversion_table_2022.txt")
CPT_table = CPT_table[-(1:8),c(1,2)]
CPT_table = CPT_table[!CPT_table[,2]=="",]
names(CPT_table)=c("CODE","dscrptn")
CPT_table$CODE_TYPE="CPT"
CPT_table$DOMAIN="CPT"

rexp <- "^(\\w+)\\s?(.*)$"
icd9_DX_table <- read.delim("Auxiliary external files--Code Descriptions/icd9_DESC_LONG_DX.txt", header=FALSE)
icd9_DX_table <- data.frame(CODE=sub(rexp,"\\1",icd9_DX_table$V1), dscrptn=sub(rexp,"\\2",icd9_DX_table$V1))
#icd9_DX_table <- colsplit(icd9_DX_table$V1," ",c("CODE","dscrptn"))
icd9_DX_table$CODE_TYPE="09"
icd9_DX_table$DOMAIN="DX"
icd9_SG_table <- read.delim("Code Descriptions/icd9_DESC_LONG_SG.txt", header=FALSE)
icd9_SG_table <- data.frame(CODE=sub(rexp,"\\1",icd9_SG_table$V1), dscrptn=sub(rexp,"\\2",icd9_SG_table$V1))
icd9_SG_table$CODE_TYPE="09"
icd9_SG_table$DOMAIN="SG"
icd9_table=rbind(icd9_DX_table,icd9_SG_table)
rm(icd9_DX_table,icd9_SG_table)
icd9_table[icd9_table$CODE=="0010",]

icd10cm_table <- read.delim("Code Descriptions/icd10cm_codes_2022.txt", header=FALSE)
icd10cm_table <- colsplit(icd10cm_table$V1," ",c("CODE","dscrptn"))
icd10cm_table$CODE_TYPE="10"
icd10cm_table$DOMAIN="CM"
icd10pcs_table <- read.delim("Code Descriptions/icd10pcs_codes_2022.txt", header=FALSE)
icd10pcs_table <- colsplit(icd10pcs_table$V1," ",c("CODE","dscrptn"))
icd10pcs_table$CODE_TYPE="10"
icd10pcs_table$DOMAIN="PCS"
icd10_table <- rbind(icd10cm_table,icd10pcs_table)
rm(icd10cm_table,icd10pcs_table)

codeDescription=rbind(icd9_table,icd10_table,CPT_table)
save(codeDescription,file="code_descriptions.RData")

icd9_table[icd9_table$CODE=="0010",]



