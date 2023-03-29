setwd("~/Desktop/Xianshi Code 2nd round")

##################################dxpxlab
load("dxpxlab_0514.RData")
names(dxpxlab)

library(dplyr)
library(Matrix)
library(readr)
library(stringr)

temp=paste(dxpxlab$CODE_TYPE,dxpxlab$CODE,sep="|")
###Add special mark for ICD-9-PX
ICD9_loc=which(dxpxlab$CODE_TYPE=="09"&dxpxlab$DOMAIN=="PX")
temp[ICD9_loc]=paste(dxpxlab$CODE_TYPE[ICD9_loc],dxpxlab$DOMAIN[ICD9_loc],dxpxlab$CODE[ICD9_loc],sep="|")

dxpxlab=cbind(dxpxlab,coTypeCode=temp)

###Index codes
codes=dxpxlab[,c("CODE","CODE_TYPE","coTypeCode")]

codes=codes[!duplicated(codes$coTypeCode),]
table(codes$CODE_TYPE)
codes <- codes %>% arrange_at(c("CODE_TYPE","CODE"))
codes=cbind(CId=1:dim(codes)[1],codes)
unique(codes$CODE[duplicated(codes$CODE)])#codes with multiple code types/domain

dxpxlab=cbind(CId=codes$CId[match(dxpxlab$coTypeCode,codes$coTypeCode)],dxpxlab)

###ICD group map
codes=cbind(codes,groupLabel=NA)
ICDGroup <- read_table("~/Desktop/Xianshi Code 2nd round/ICD-CM to phecode, unrolled.txt")
table(ICDGroup$flag)
temp=strsplit(ICDGroup$phecode, "\\.")
phe_temp=NULL
for(i in 1:dim(ICDGroup)[1]){
  if(length(temp[[i]])==1){
    phe_temp=c(phe_temp,ICDGroup$phecode[i])#c(phe_temp,paste(temp[[i]],"0",sep="."))
  }else if(nchar(temp[[i]][2])==1){
    phe_temp=c(phe_temp,ICDGroup$phecode[i])
  }else{
    phe_temp=c(phe_temp,paste(temp[[i]][1],substr(temp[[i]][2], 1, 1),sep="."))
  }
}
ICDGroup=cbind(ICDGroup,phecodeN=phe_temp)
ICDGroup$flag=as.character(ICDGroup$flag)
ICDGroup$flag[ICDGroup$flag=="9"]="09"

temp=paste(ICDGroup$flag,ICDGroup$ICD,sep="|")
ICDGroup=cbind(ICDGroup,coTypeCode=temp)
library(dplyr)

ICDGroup=ICDGroup%>%arrange(ICD,desc(phecodeN))
####Note that group map is not done for ICD-9-PX due to format issue (this only increase ungrouped codes by 0.2%, of all ICD codes)
codes$groupLabel=ICDGroup$phecodeN[match(codes$coTypeCode,ICDGroup$coTypeCode)]

temp=subset(codes,CODE_TYPE%in%c("09","10"))
sum(is.na(temp$groupLabel))/dim(temp)[1]#25.59% ICD codes without group label
nICDgroup=length(na.omit(unique(temp$groupLabel)))

###CPT group map
CPTGroup<- read_csv("~/Desktop/Xianshi Code 2nd round/CCS_services_procedures_v2021-1.csv", col_types = cols(CCS = col_character()), skip = 1)
CPTGroup<- CPTGroup[1:11742,]#EXCLUDE SELECTED CODES-XU

CPTGroup$`Code Range`=sub("'", "", CPTGroup$`Code Range`)
CPTGroup$`Code Range`=sub("'", "", CPTGroup$`Code Range`)
temp=strsplit(CPTGroup$`Code Range`, "-")
range_temp=NULL
for(i in 1:dim(CPTGroup)[1]){
  range_temp=rbind(range_temp,temp[[i]])
}
CPTGroup=cbind(rangeFrom=range_temp[,1],rangeTo=range_temp[,2],CPTGroup)

###Confirm that all CPT have length=5 
#table(nchar(CPTGroup$rangeFrom))
#table(nchar(CPTGroup$rangeTo))
#table(nchar(codes$CODE[codes$CODE_TYPE%in%c("C2","C3","C4")]))

for(i in 1:dim(codes)[1]){
  if(!codes$CODE_TYPE[i]%in%c("C2","C3","C4")){next}
  
  temp1=which(codes$CODE[i]>=CPTGroup$rangeFrom&codes$CODE[i]<=CPTGroup$rangeTo)
  if(length(temp1)==0){
    next
  }else if(length(temp1)>1){
    warning("CPT code matches multiple groups!")
  }else{
    codes$groupLabel[i]=CPTGroup$CCS[temp1]
  }
  
}

temp=subset(codes,CODE_TYPE%in%c("C2","C3","C4"))
sum(is.na(temp$groupLabel))/dim(temp)[1]#10% CPT codes without group label
nCPTgroup=length(na.omit(unique(temp$groupLabel)))

rm(temp,i,phe_temp,temp1,range_temp)

##################################patients
load("patients_0514.RData")
patients=patients_ELIGIBLE
temp=patients$SITE[match(dxpxlab$STUDYID,patients$STUDYID)]
dxpxlab=cbind(SITE=temp,dxpxlab)

###check for abnormalty
table(patients$RACE)
table(patients$SEXF)
table(patients$HISPANIC)
sum(duplicated(patients$STUDYID))
table(as.matrix(patients[,8:16],nrow=1))

###PId
library(dplyr)
patients<-patients%>%arrange(SITE,STUDYID)
patients_OBSERVED<-patients_OBSERVED%>%arrange(SITE,STUDYID)
patients=cbind(PId=1:dim(patients)[1],patients)
patients_OBSERVED=cbind(PId=patients$PId[match(patients_OBSERVED$STUDYID,patients$STUDYID)],patients_OBSERVED)

###factors
patients$RACE=factor(patients$RACE)
patients$SEXF=factor(patients$SEXF)
patients$HISPANIC=factor(patients$HISPANIC)

patients_OBSERVED$RACE=factor(patients_OBSERVED$RACE)
patients_OBSERVED$SEXF=factor(patients_OBSERVED$SEXF)
patients_OBSERVED$HISPANIC=factor(patients_OBSERVED$HISPANIC)

dxpxlab=cbind(PId=patients$PId[match(dxpxlab$STUDYID,patients$STUDYID)],dxpxlab)
codeRecord=cbind(dxpxlab,Year=format(dxpxlab$DPL_DATE,"%Y"))
rm(dxpxlab)

patients_ELIGIBLE=patients
rm(patients)

###GId
"NA"%in%codes$groupLabel
codes$groupLabel[is.na(codes$groupLabel)]="NA"
codeGroup=distinct(codes[,c("CODE_TYPE","groupLabel")])
codeGroup=cbind(GId=NA,codeGroup)
#codeGroup$CODE_TYPE[codeGroup$groupLabel=="NA"]="ANY"
codeGroup=codeGroup%>%arrange(CODE_TYPE,groupLabel)
temp=which(codeGroup$groupLabel=="NA")
codeGroup=codeGroup[-temp,]
codeGroup$GId=1:dim(codeGroup)[1]
rownames(codeGroup) <- 1:nrow(codeGroup)

codes=merge(codes,codeGroup,by=c("CODE_TYPE","groupLabel"),all.x=T,all.y=F)

################codes$freq
temp=table(codeRecord$CId)
freq_temp=as.data.frame(temp,stringsAsFactors=F)
freq_temp$Var1=as.integer(freq_temp$Var1)
codes=cbind(codes,freq=freq_temp$Freq[match(codes$CId,freq_temp$Var1)])

temp=table(codeRecord$CId[codeRecord$SITE==1])
freq_temp=as.data.frame(temp,stringsAsFactors=F)
freq_temp$Var1=as.integer(freq_temp$Var1)
temp=freq_temp$Freq[match(codes$CId,freq_temp$Var1)]
temp[is.na(temp)]=0
codes=cbind(codes,freq_SITE1=temp)

temp=table(codeRecord$CId[codeRecord$SITE==2])
freq_temp=as.data.frame(temp,stringsAsFactors=F)
freq_temp$Var1=as.integer(freq_temp$Var1)
temp=freq_temp$Freq[match(codes$CId,freq_temp$Var1)]
temp[is.na(temp)]=0
codes=cbind(codes,freq_SITE2=temp)
rm(temp,freq_temp)

###Create coarse group label for ICD codes
#table(ICDGroup$phecodeN)
coarseLabel=word(codes$groupLabel, 1,sep = "\\.")
codes=cbind(codes,coarseLabel=coarseLabel)
temp=(!codes$CODE_TYPE%in%c("09","10"))
codes$coarseLabel[temp]=codes$groupLabel[temp]
rm(temp,coarseLabel,ICD9_loc)

###Frequency for groups
coarseGroup_freq<- codes %>%
  group_by(CODE_TYPE,coarseLabel) %>%
  summarise(freq = sum(freq),freq_SITE1=sum(freq_SITE1),freq_SITE2=sum(freq_SITE2))

Group_freq<- codes %>%
  group_by(GId) %>%
  summarise(Freq = sum(freq),freq_SITE1=sum(freq_SITE1),freq_SITE2=sum(freq_SITE2))

codeGroup=merge(codeGroup,Group_freq,by="GId",all.x=T,all.y=F)
rm(Group_freq)

codes=codes[order(codes$CId),]

###Add code group descriptions
load("~/Desktop/Xianshi Code 2nd round/phecode_descriptions.RData")
temp=phecode_definitions$phenotype[match(codeGroup$groupLabel,phecode_definitions$phecode)]
temp[!codeGroup$CODE_TYPE%in%c("09","10")]=NA
description=temp
temp=CPTGroup$`CCS Label`[match(codeGroup$groupLabel,CPTGroup$CCS)]
description[codeGroup$CODE_TYPE%in%c("C2","C3","C4")]=temp[codeGroup$CODE_TYPE%in%c("C2","C3","C4")]
codeGroup=cbind(codeGroup,description)
names(codeGroup)[5:6]=c("freq_KPWA","freq_KPNW")
rm(description,temp)

###Add code description
load("~/Desktop/Xianshi Code 2nd round/code_descriptions.RData")
coTypeCode=paste(codeDescription$CODE_TYPE,codeDescription$CODE,sep="|")
coTypeCode[codeDescription$CODE_TYPE%in%c("09","10")&codeDescription$DOMAIN%in%c("PCS","SG")]=paste(codeDescription$CODE_TYPE,"PX",codeDescription$CODE,sep="|")[codeDescription$CODE_TYPE%in%c("09","10")&codeDescription$DOMAIN%in%c("PCS","SG")]
codeDescription=cbind(codeDescription,coTypeCode)
rm(coTypeCode)

temp_coTypeCode=sub("\\.", "", codes$coTypeCode)
temp_coTypeCode[codes$CODE_TYPE%in%c("C2","C3","C4")]=paste("CPT",codes$CODE,sep="|")[codes$CODE_TYPE%in%c("C2","C3","C4")]

description=codeDescription$dscrptn[match(temp_coTypeCode,codeDescription$coTypeCode)]
codes=cbind(codes,description)
rm(description,temp_coTypeCode)

rownames(codes) <- 1:nrow(codes)

###Factors
temp.names=c("SITE","HISPANIC","RACE","SEXF",
             "COMOR_CVD_FIRSTELIG","COMOR_CKD_FIRSTELIG","COMOR_CHF_FIRSTELIG",
             "COMOR_DEP_FIRSTELIG", "INSULIN_FIRSTELIG","OTHMED_FIRSTELIG")
                       
for(name in temp.names){
  patients_OBSERVED[,name]=factor(patients_OBSERVED[,name])
  patients_ELIGIBLE[,name]=factor(patients_ELIGIBLE[,name])
}

temp.names=c("COMOR_CVD_FIRSTOBS_MINUS1","COMOR_CKD_FIRSTOBS_MINUS1","COMOR_CHF_FIRSTOBS_MINUS1",
"COMOR_DEP_FIRSTOBS_MINUS1", "INSULIN_FIRSTOBS_MINUS1","OTHMED_FIRSTOBS_MINUS1","MEDICAID_FIRSTOBS")

for(name in temp.names){
  patients_OBSERVED[,name]=factor(patients_OBSERVED[,name])
}

rm(temp.names)

###Add frequency ratio
patient_year=cbind(SITE=patients_ELIGIBLE$SITE[match(patient_year$STUDYID,patients_ELIGIBLE$STUDYID)],patient_year)
npatient_year_site1=sum(patient_year$ENROLLMTH_OBS>=1&patient_year$SITE==1)
npatient_year_site2=sum(patient_year$ENROLLMTH_OBS>=1&patient_year$SITE==2)
codes=cbind(codes,frequency_ratio_KPWA_over_KPNW=(codes$freq_SITE1+10)/npatient_year_site1/((codes$freq_SITE2+10)/npatient_year_site2))

npatient_OBSERVED_site1=sum(patients_OBSERVED$SITE==1)
npatient_OBSERVED_site2=sum(patients_OBSERVED$SITE==2)

###Obtain day_cnt_per_mth for person_year
temp=paste(codeRecord$STUDYID,codeRecord$DPL_DATE,sep=" ")
temp1=unique(temp)
temp2=strsplit(temp1, split = " ")

temp=as.data.frame(matrix(unlist(temp2),ncol=2,byrow = T))
temp$V2=as.Date(temp$V2)
Year=format(temp$V2,"%Y")
temp=cbind(temp,YEAR_OBS=as.numeric(Year))
names(temp)[1]="STUDYID"
temp1<-temp%>%dplyr::group_by(STUDYID,YEAR_OBS)%>%dplyr::summarise(DAY_CNT = n())
patient_year=merge(patient_year,temp1,by=c("STUDYID","YEAR_OBS"),all.x=T,all.y=F)
patient_year$DAY_CNT[is.na(patient_year$DAY_CNT)]=0
DAY_CNT_per_MTH=patient_year$DAY_CNT/patient_year$ENROLLMTH_OBS
patient_year=cbind(patient_year,DAY_CNT_per_MTH)
rm(temp,temp1,temp2,Year,DAY_CNT_per_MTH);gc()

#save(patient_year,file="patient_year_with_DAY_CNT_0621.RData")

save.image(file="H:/Desktop/Xianshi Code 2nd round/dxpxlab_processed_0514.RData")

##########################Observe Data
load("H:/Desktop/Xianshi Code 2nd round/dxpxlab_processed_0514.RData")

library(dplyr)
library(boot)
library(table1)
library(magrittr)
library(flextable)

levels(patients_OBSERVED$SITE)=c("KPWA","KPNW")
levels(patients_OBSERVED$RACE)=c("Unknown","American Indian or Alaska Native",
                                 "Asian","Black or African American","Native Hawaiian or Other Pacific Islander",
                                 "White")
levels(patients_OBSERVED$HISPANIC)=c("No","unknown","Yes")
temp=cut(patients_OBSERVED$COMOR_IND_E1_FIRSTOBS_MINUS1,breaks=c(0,1.5,3.5,5.5,20.5),right=F)
patients_OBSERVED=cbind(patients_OBSERVED,COMOR_IND_E1_FIRSTOBS_MINUS1_cut=temp)

temp.names=c("SITE", "AGE_AT_FIRSTOBS_MINUS1","SEXF","INSULIN_FIRSTOBS_MINUS1","COMOR_IND_E1_FIRSTOBS_MINUS1","COMOR_IND_E1_FIRSTOBS_MINUS1_cut",
             "RACE","HISPANIC",
             "HOSP_CNT_FIRSTOBS_MINUS1", "AMBUL_CNT_FIRSTOBS_MINUS1",
             "BMI_LAST_FIRSTOBS_MINUS1", "A1C_LAST_FIRSTOBS_MINUS1", "MED_CNT_FIRSTOBS_MINUS1",
             "OTHMED_FIRSTOBS_MINUS1","MEDICAID_FIRSTOBS",
             "COMOR_CVD_FIRSTOBS_MINUS1","COMOR_CKD_FIRSTOBS_MINUS1","COMOR_CHF_FIRSTOBS_MINUS1","COMOR_DEP_FIRSTOBS_MINUS1",
             "COMOR_IND_E2_FIRSTOBS_MINUS1","COMOR_IND_C_FIRSTOBS_MINUS1","YEAR_AT_FIRSTOBS","PY_TOTAL_1PLUS_MTH")          
#patients_OBSERVED=patients_OBSERVED[,temp.names]
fml=paste(temp.names[-1],collapse = "+")
fml=paste("~",fml," | SITE",sep="")

Plus9_patientOnly=T
if(Plus9_patientOnly){
  pSet=unique(subset(patient_year,ENROLLMTH_OBS>=9)$STUDYID)
}else{
  pSet=patients_OBSERVED$STUDYID
}
tab1=table1(as.formula(fml), data=subset(patients_OBSERVED,STUDYID%in%pSet), overall="Total")
setwd("~/Desktop/Xianshi Code 2nd round")
t1flex(tab1) %>% save_as_docx(path="Table1.docx")
write.table (tab1 , "my_table_1_file.csv", col.names = T, row.names=F, append= T, sep=',')
saveWidget(tab1, file = "Table1.html")


####Multilevel variables
table(patients_OBSERVED$SITE,patients_OBSERVED$HISPANIC)
table(patients_OBSERVED$SITE,patients_OBSERVED$RACE)
table(patients_OBSERVED$SITE,patients_OBSERVED$SEXF)

####Binary variables
temp.binary.names=c("SEXF","COMOR_CVD_FIRSTOBS_MINUS1","COMOR_CKD_FIRSTOBS_MINUS1","COMOR_CHF_FIRSTOBS_MINUS1",
                    "COMOR_DEP_FIRSTOBS_MINUS1", "INSULIN_FIRSTOBS_MINUS1","OTHMED_FIRSTOBS_MINUS1","MEDICAID_FIRSTOBS")
patients_temp=patients_OBSERVED[,c("SITE",temp.binary.names)]
for(name in temp.binary.names){
  patients_temp[,name]=as.numeric(as.character(patients_temp[,name]))
}
                                
                                
sum_binary<-patients_temp%>%group_by(SITE) %>% summarize_all(sum)
sum_binary[1,-1]=round(sum_binary[1,-1]/sum(patients_OBSERVED$SITE=="KPWA")*100,2)
sum_binary[2,-1]=round(sum_binary[2,-1]/sum(patients_OBSERVED$SITE=="KPNW")*100,2)

View(sum_binary)

#rate ratio: [(frequency+10)/patient_year]_site1/[(frequency+10)/patient_year]_site2

###Numerical variables
temp.nonbinary.names=setdiff(temp.names,temp.binary.names)
temp.numeric.names=setdiff(temp.nonbinary.names,c("HISPANIC","RACE"))
temp.numeric.names

setwd("~/Desktop/Xianshi Code 2nd round")
pdf(file="Data_summaries_numeric.pdf",width = 10,height=8)
library(ggplot2)

p<-ggplot(patients_OBSERVED, aes(x=YEAR_AT_FIRSTOBS, fill=SITE, color=SITE)) +
  geom_histogram(position="identity", alpha=0.3,bins=30)
print(p)

p<-ggplot(patients_OBSERVED, aes(x=PY_TOTAL_1PLUS_MTH, fill=SITE, color=SITE)) +
  geom_histogram(position="identity", alpha=0.3,bins=30)
print(p)

p<-ggplot(patients_OBSERVED, aes(x=AGE_AT_FIRSTOBS_MINUS1, fill=SITE, color=SITE)) +
  geom_histogram(position="identity", alpha=0.3,bins=30)
print(p)

p<-ggplot(patients_OBSERVED, aes(x=HOSP_CNT_FIRSTOBS_MINUS1, fill=SITE, color=SITE)) +
  geom_histogram(position="identity", alpha=0.3,bins=30)
print(p)

p<-ggplot(patients_OBSERVED, aes(x=AMBUL_CNT_FIRSTOBS_MINUS1, fill=SITE, color=SITE)) +
  geom_histogram(position="identity", alpha=0.3,bins=30)
print(p)

p<-ggplot(patients_OBSERVED, aes(x=BMI_LAST_FIRSTOBS_MINUS1, fill=SITE, color=SITE)) +
  geom_histogram(position="identity", alpha=0.3,bins=30)
print(p)

p<-ggplot(patients_OBSERVED, aes(x=A1C_LAST_FIRSTOBS_MINUS1, fill=SITE, color=SITE)) +
  geom_histogram(position="identity", alpha=0.3,bins=30)
print(p)

p<-ggplot(patients_OBSERVED, aes(x=MED_CNT_FIRSTOBS_MINUS1, fill=SITE, color=SITE)) +
  geom_histogram(position="identity", alpha=0.3,bins=30)
print(p)

p<-ggplot(patients_OBSERVED, aes(x=COMOR_IND_E1_FIRSTOBS_MINUS1, fill=SITE, color=SITE)) +
  geom_histogram(position="identity", alpha=0.3,bins=30)
print(p)

p<-ggplot(patients_OBSERVED, aes(x=COMOR_IND_E2_FIRSTOBS_MINUS1, fill=SITE, color=SITE)) +
  geom_histogram(position="identity", alpha=0.3,bins=30)
print(p)

p<-ggplot(patients_OBSERVED, aes(x=COMOR_IND_C_FIRSTOBS_MINUS1, fill=SITE, color=SITE)) +
  geom_histogram(position="identity", alpha=0.3,bins=30)
print(p)

dev.off()

##########################Earlier code for KPWA data
# setwd("~/Desktop/Xianshi Code 2nd round")
# 
# ##################################dxpxlab
# load("dxpxlab_0315.RData")
# names(dxpxlab)
# 
# library(dplyr)
# library(Matrix)
# library(readr)
# library(stringr)
# 
# temp=paste(dxpxlab$CODE_TYPE,dxpxlab$CODE,sep="|")
# ###Add special mark for ICD-9-PX
# ICD9_loc=which(dxpxlab$CODE_TYPE=="09"&dxpxlab$DOMAIN=="PX")
# temp[ICD9_loc]=paste(dxpxlab$CODE_TYPE[ICD9_loc],dxpxlab$DOMAIN[ICD9_loc],dxpxlab$CODE[ICD9_loc],sep="|")
# 
# dxpxlab=cbind(dxpxlab,coTypeCode=temp)
# 
# ###Index codes
# codes=dxpxlab[,c("CODE","CODE_TYPE","coTypeCode")]
# 
# codes=codes[!duplicated(codes$coTypeCode),]
# table(codes$CODE_TYPE)
# codes <- codes %>% arrange_at(c("CODE_TYPE","CODE"))
# codes=cbind(CId=1:dim(codes)[1],codes)
# unique(codes$CODE[duplicated(codes$CODE)])#codes with multiple code types/domain
# 
# dxpxlab=cbind(CId=codes$CId[match(dxpxlab$coTypeCode,codes$coTypeCode)],dxpxlab)
# 
# ###ICD group map
# codes=cbind(codes,groupLabel=NA)
# ICDGroup <- read_table("~/Desktop/Xianshi Code 2nd round/ICD-CM to phecode, unrolled.txt")
# table(ICDGroup$flag)
# temp=strsplit(ICDGroup$phecode, "\\.")
# phe_temp=NULL
# for(i in 1:dim(ICDGroup)[1]){
#   if(length(temp[[i]])==1){
#     phe_temp=c(phe_temp,ICDGroup$phecode[i])#c(phe_temp,paste(temp[[i]],"0",sep="."))
#   }else if(nchar(temp[[i]][2])==1){
#     phe_temp=c(phe_temp,ICDGroup$phecode[i])
#   }else{
#     phe_temp=c(phe_temp,paste(temp[[i]][1],substr(temp[[i]][2], 1, 1),sep="."))
#   }
# }
# ICDGroup=cbind(ICDGroup,phecodeN=phe_temp)
# ICDGroup$flag=as.character(ICDGroup$flag)
# ICDGroup$flag[ICDGroup$flag=="9"]="09"
# 
# temp=paste(ICDGroup$flag,ICDGroup$ICD,sep="|")
# ICDGroup=cbind(ICDGroup,coTypeCode=temp)
# library(dplyr)
# 
# ICDGroup=ICDGroup%>%arrange(ICD,desc(phecodeN))
# ####Note that group map is not done for ICD-9-PX due to format issue (this only increase ungrouped codes by 0.2%, of all ICD codes)
# codes$groupLabel=ICDGroup$phecodeN[match(codes$coTypeCode,ICDGroup$coTypeCode)]
# 
# temp=subset(codes,CODE_TYPE%in%c("09","10"))
# sum(is.na(temp$groupLabel))/dim(temp)[1]#22.64% ICD codes without group label
# nICDgroup=length(na.omit(unique(temp$groupLabel)))
# 
# ###CPT group map
# CPTGroup<- read_csv("~/Desktop/Xianshi Code 2nd round/CCS_services_procedures_v2021-1.csv", col_types = cols(CCS = col_character()), skip = 1)
# CPTGroup<- CPTGroup[1:11742,]#EXCLUDE SELECTED CODES-XU
# 
# CPTGroup$`Code Range`=sub("'", "", CPTGroup$`Code Range`)
# CPTGroup$`Code Range`=sub("'", "", CPTGroup$`Code Range`)
# temp=strsplit(CPTGroup$`Code Range`, "-")
# range_temp=NULL
# for(i in 1:dim(CPTGroup)[1]){
#   range_temp=rbind(range_temp,temp[[i]])
# }
# CPTGroup=cbind(rangeFrom=range_temp[,1],rangeTo=range_temp[,2],CPTGroup)
# 
# ###Confirm that all CPT have length=5 
# #table(nchar(CPTGroup$rangeFrom))
# #table(nchar(CPTGroup$rangeTo))
# #table(nchar(codes$CODE[codes$CODE_TYPE%in%c("C2","C3","C4")]))
# 
# for(i in 1:dim(codes)[1]){
#   if(!codes$CODE_TYPE[i]%in%c("C2","C3","C4")){next}
#   
#   temp1=which(codes$CODE[i]>=CPTGroup$rangeFrom&codes$CODE[i]<=CPTGroup$rangeTo)
#   if(length(temp1)==0){
#     next
#   }else if(length(temp1)>1){
#     warning("CPT code matches multiple groups!")
#   }else{
#     codes$groupLabel[i]=CPTGroup$CCS[temp1]
#   }
#   
# }
# 
# temp=subset(codes,CODE_TYPE%in%c("C2","C3","C4"))
# sum(is.na(temp$groupLabel))/dim(temp)[1]#8.1% CPT codes without group label
# nCPTgroup=length(na.omit(unique(temp$groupLabel)))
# 
# rm(codes_temp,temp,code_types_temp,i,phe_temp,type,temp1,range_temp)
# 
# ##################################patients
# load("patients_0315.RData")
# 
# ###check for abnormalty
# table(patients$Race)
# table(patients$SEXF)
# table(patients$hispanic)
# sum(duplicated(patients$STUDYID))
# table(as.matrix(patients[,11:19],nrow=1))
# 
# ###PId
# patients=patients[order(patients$STUDYID),]
# patients=cbind(PId=1:dim(patients)[1],patients)
# 
# ###factors
# patients$Race=factor(patients$Race)
# patients$SEXF=factor(patients$SEXF)
# patients$hispanic=factor(patients$hispanic)
# 
# dxpxlab=cbind(PId=patients$PId[match(dxpxlab$STUDYID,patients$STUDYID)],dxpxlab)
# codeRecord=cbind(dxpxlab,Year=format(dxpxlab$DPL_DATE,"%Y"))
# rm(dxpxlab)
# 
# ###GId
# "NA"%in%codes$groupLabel
# codes$groupLabel[is.na(codes$groupLabel)]="NA"
# codeGroup=data.frame(GId=NA,codes[!duplicated(codes$groupLabel),c("CODE_TYPE","groupLabel")])
# codeGroup$CODE_TYPE[codeGroup$groupLabel=="NA"]="ANY"
# codeGroup=codeGroup%>%arrange(CODE_TYPE,groupLabel)
# temp=which(codeGroup$groupLabel=="NA")
# codeGroup=rbind(codeGroup[temp,],codeGroup[-temp,])
# codeGroup$GId=1:dim(codeGroup)[1]
# codes=cbind(codes,GId=codeGroup$GId[match(codes$groupLabel,codeGroup$groupLabel)])
# 
# ################codes$freq
# temp=table(codeRecord$CId)
# freq_temp=as.data.frame(temp,stringsAsFactors=F)
# freq_temp$Var1=as.integer(freq_temp$Var1)
# codes=cbind(codes,freq=freq_temp$Freq[match(codes$CId,freq_temp$Var1)])
# rm(temp,freq_temp)
# 
# ###Create coarse group label for ICD codes
# #table(ICDGroup$phecodeN)
# coarseLabel=word(codes$groupLabel, 1,sep = "\\.")
# codes=cbind(codes,coarseLabel=coarseLabel)
# temp=(!codes$CODE_TYPE%in%c("09","10"))
# codes$coarseLabel[temp]=codes$groupLabel[temp]
# rm(temp,coarseLabel,ICD9_loc)
# 
# ###Frequency for groups
# coarseGroup_freq<- codes %>%
#   group_by(coarseLabel) %>%
#   summarise(Freq = sum(freq))
# 
# Group_freq<- codes %>%
#   group_by(groupLabel) %>%
#   summarise(Freq = sum(freq))
# 
# codeGroup=cbind(codeGroup,freq=Group_freq$Freq[match(codeGroup$groupLabel,Group_freq$groupLabel)])
# rm(Group_freq)
# 
# save.image(file="dxpxlab_processed_0315.RData")
# 
# ###########################################Summary for groups
# codeGroup_ordered=codeGroup[order(codeGroup$freq),]
# coarseGroup_ordered=coarseGroup_freq[order(coarseGroup_freq$Freq),]
# 
# 
# 
# ###########################################ISSUE with stripping desimal
# #dim(unique(codeRecord[,c("CODE","CODE_TYPE","DOMAIN")]))
# #dim(unique(codeRecord[,c("CODE","CODE_TYPE")]))
# temp_unique=unique(codeRecord[,c("CODE","CODE_TYPE","DOMAIN")])
# loc_temp=duplicated(temp_unique[,c("CODE","CODE_TYPE")])
# loc_temp=which(loc_temp)
# 
# i=1;dups=temp[temp_unique$CODE==temp_unique$CODE[loc_temp[i]],]
# for(i in 2:length(loc_temp)){
#   dups=rbind(dups,temp_unique[temp$CODE==temp_unique$CODE[loc_temp[i]],])
# }
# dups
# row.names(dups)=1:dim(dups)[1]
# save(dups,file="dupplication_in_codes.RData")
# 
# ################################################
# #                  View Data                   #
# ################################################
# codeCat<-dxpxlab%>%count(DOMAIN,CODE_TYPE)
# codeCat
# 
# allICD9=unique(subset(dxpxlab,CODE_TYPE=="09")$CODE)
# allICD9[sample(1:length(allICD9),100)]
# 
# allICD10=unique(subset(dxpxlab,CODE_TYPE=="10")$CODE)
# allICD10[sample(1:length(allICD10),100)]
# 
# allCPT=unique(subset(dxpxlab,CODE_TYPE%in%c("C2","C3","C4"))$CODE)
# allCPT[sample(1:length(allCPT),100)]
# 
# allLoinc=unique(subset(dxpxlab,CODE_TYPE=="LC")$CODE)
# allLoinc[sample(length(allLoinc),100)]
# 
# sum(!allICD9%in%ICD9Group$ICD)/length(allICD9)*100
# allICD9[!allICD9%in%ICD9Group$ICD]
# 
# sum(!allICD10%in%ICD10Group$ICD)/length(allICD10)*100
# allICD10[!allICD10%in%ICD10Group$ICD]
# 
# #sum(!allICD9%in%c(ICD9Group$ICD,ICD10Group$ICD))/length(allICD9)*100
# #sum(!allICD10%in%c(ICD9Group$ICD,ICD10Group$ICD))/length(allICD10)*100
# 
# ###
# 
# allPX=unique(subset(dxpxlab,DOMAIN=="PX")$CODE)
# allPX[sample(length(allPX),100)]
# 
# allLAP_P=unique(subset(dxpxlab,DOMAIN=="LAB_P")$CODE)#CPT
# allLAP_L=unique(subset(dxpxlab,DOMAIN=="LAB_L")$CODE)


