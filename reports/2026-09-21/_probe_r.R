args <- commandArgs(trailingOnly=TRUE)
ip <- installed.packages(noCache=TRUE)
write.csv(data.frame(Package=ip[,"Package"], Version=ip[,"Version"], Built=ip[,"Built"], Library=ip[,"LibPath"]),args[1],row.names=FALSE,fileEncoding="UTF-8")
write.csv(data.frame(Version=R.version.string, RHome=R.home(), Library=.libPaths(), Writable=file.access(.libPaths(),2)==0),args[2],row.names=FALSE,fileEncoding="UTF-8")