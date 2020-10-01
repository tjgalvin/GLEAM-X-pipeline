#! /bin/bash

#set -x

usage()
{
echo "obs_autoflag.sh [-p project] [-a account] [-d dep] [-t] obsnum
  -p project : project, no default
  -a account : computing account, default pawsey0272
  -d dep     : job number for dependency (afterok)
  -t         : test. Don't submit job, just make the batch file
               and then return the submission command
  obsnum     : the obsid to process, or a text file of obsids (newline separated). 
               A job-array task will be submitted to process the collection of obsids. " 1>&2;
exit 1;
}

pipeuser="${GXUSER}"

dep=
tst=

# parse args and set options
while getopts ':td:a:p:' OPTION
do
    case "$OPTION" in
	d)
	    dep=${OPTARG}
	    ;;
	a)
	    account=${OPTARG}
	    ;;
	p)
	    project=${OPTARG}
	    ;;
	t)
	    tst=1
	    ;;
	? | : | h)
	    usage
	    ;;
  esac
done
# set the obsid to be the first non option
shift  "$(($OPTIND -1))"
obsnum=$1

# if obsid or project are empty then just pring help
if [[ -z ${obsnum} ]] || [[ -z ${project} ]]
then
    usage
fi

if [[ -z ${account} ]]
then
    account=pawsey0272
fi

# Establish job array options
if [[ -f ${obsnum} ]]
then
    # echo "${obsnum} is a file that exists, proceeding with job-array set up"
    numfiles=$(wc -l "${obsnum}" | awk '{print $1}')
    arrayline="#SBATCH --array=1-${numfiles}"
else
    numfiles=1
    arrayline=''
fi

queue="-p ${GXSTANDARDQ}"
datadir="${GXSCRATCH}/${project}"

# set dependency
if [[ ! -z ${dep} ]]
then
    if [[ -f ${obsnum} ]]
    then
        depend="--dependency=aftercorr:${dep}"
    else
        depend="--dependency=afterok:${dep}"
    fi
fi

script="${GXBASE}/queue/autoflag_${obsnum}.sh"

cat "${GXBASE}/bin/autoflag.tmpl" | sed -e "s:OBSNUM:${obsnum}:g" \
                                     -e "s:DATADIR:${datadir}:g" \
                                     -e "s:HOST:${GXCOMPUTER}:g" \
                                     -e "s:TASKLINE:${GXTASKLINE}:g" \
                                     -e "s:STANDARDQ:${GXSTANDARDQ}:g" \
                                     -e "s:ACCOUNT:${account}:g" \
                                     -e "s:PIPEUSER:${pipeuser}:g" \
                                     -e "s:ARRAYLINE:${arrayline}:g"> "${script}"

output="${GXLOG}/autoflag_${obsnum}.o%A"
error="${GXLOG}/autoflag_${obsnum}.e%A"
if [[ -f ${obsnum} ]]
then
    output="${output}_%a"
    error="${error}_%a"
fi

sub="sbatch -M ${GXCOMPUTER} --output=${output} --error=${error} --begin=now+120 ${depend} ${queue} ${script}"

if [[ ! -z ${tst} ]]
then
    echo "script is ${script}"
    echo "submit via:"
    echo "${sub}"
    exit 0
fi

# submit job
jobid=($(${sub}))
jobid=${jobid[3]}

echo "Submitted ${script} as ${jobid} Follow progress here:"

for taskid in $(seq ${numfiles})
do
    # rename the err/output files as we now know the jobid
    obserror=$(echo "${error}" | sed -e "s/%A/${jobid}/" -e "s/%a/${taskid}/")
    obsoutput=$(echo "${output}" | sed -e "s/%A/${jobid}/" -e "s/%a/${taskid}/")
    
    if [[ -f ${obsnum} ]]
    then
        obs=$(sed -n -e "${taskid}"p "${obsnum}")
    else
        obs=$obsnum
    fi

    # record submission
    track_task.py queue --jobid="${jobid}" --taskid="${taskid}" --task='flag' --submission_time="$(date +%s)"\
                        --batch_file="${script}" --obs_id="${obs}" --stderr="${obserror}" --stdout="${obsoutput}"

    echo "$obsoutput"
    echo "$obserror"
done

