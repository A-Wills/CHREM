# Use this shell 
#$ -S /bin/bash 
# Run from current directory 
#$ -cwd 
# Name that appears in qstat 
#$ -N Remove_HOUSE
# Memory allocated 
#$ -l h_vmem=2G 
# Run time for each simulation 
#$ -l h_rt=02:00:00 
# mail when job ends 
#$ -m e 
#$ -M s.nikoofard@dal.ca 
# Run 1 times with SGE_TASK_ID going 
# From 1 to 1, stepping by 1 
#$ -t 1:1:1 
rm -f -r 2-DR_WTM2010_CFC_30