phecode_definitions <- read.csv("~/Desktop/Xianshi Code 2nd round/phecode_definitions1.2.csv")
library(stringr)

decimal=sub('.*\\.', '', phecode_definitions$phecode)
IS_decimal=str_detect(phecode_definitions$phecode,"\\.")

#phecode_definitions$phecode
replacement=rep(NA,dim(phecode_definitions)[1])
replacement[!IS_decimal]=sprintf('%03d', as.numeric(sub('\\..*', '', phecode_definitions$phecode)))[!IS_decimal]
replacement[IS_decimal]=sprintf('%03d.%s', as.numeric(sub('\\..*', '', phecode_definitions$phecode)),decimal)[IS_decimal]

#cbind(phecode_definitions$phecode,replacement)[1:20,]
phecode_definitions$phecode=replacement;rm(replacement)

setwd("~/Desktop/Xianshi Code 2nd round")
save(phecode_definitions,file="phecode_descriptions.RData")
