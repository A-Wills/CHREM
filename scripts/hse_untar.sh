# Use this shell 
#$ -S /bin/bash 
# Run from current directory 
#$ -cwd 
# Name that appears in qstat 
#$ -N TAR_HOUSE
# Memory allocated 
#$ -l h_vmem=2G 
# Run time for each simulation 
#$ -l h_rt=01:00:00 
# mail when job ends 
#$ -m e 
#$ -M s.nikoofard@dal.ca 
# Run 1 times with SGE_TASK_ID going 
# From 1 to 1, stepping by 1 
#$ -t 1:1:1 
tar -zxf 1-SD_WTM2010_CFC_10.tar.gz