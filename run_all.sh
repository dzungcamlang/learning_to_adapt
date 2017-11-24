#!/bin/bash

. cmd.sh
. path.sh

nj=4
dir=exp/all_256_supervised_10s
configs=$dir/configs
mkdir -p $configs
rm -rf $configs/*
for lr in 0.001 0.01 0.1 0.2; do
    for epochs in 1 3 5; do
        name="all_${lr}_${epochs}"
        echo "{\"lr\": $lr, \"epochs\": $epochs}" > $configs/$name.json
        echo -e "${name}\t${configs}/${name}.json" >> $configs/experiments.scp
    done
done

mkdir -p $configs/split${nj}
for job in `seq 1 $nj`; do
    utils/split_scp.pl -j $nj $((job-1)) $configs/experiments.scp $configs/split${nj}/$job.scp
done

for dataset in dev2010 tst2010 tst2011; do
    data=data/${dataset}
    pdfs=exp/dnn_256-7-small_softmax-dbn_dnn/decode_${dataset}/ali/
    pdfs="exp/dnn_256-7-small_softmax-dbn_dnn/align_${dataset}/"
    frames=1000
    model=exp/model/
    graph=exp/model/graph_TED-312MW.3gm.p07/
    decode_dir=$dir/decode_${dataset}

    # Create splits by speakers
    cut -f 1 -d ' ' $data/spk2utt > $data/spks_list
    num_spks=`cat $data/spks_list | wc -l`

    mkdir -p $data/spks_split
    for i in `seq $num_spks`; do
        splitdir=$data/spks_split/$i/

        mkdir -p $splitdir
        sed -n "${i}p" $data/spks_list > $splitdir/spks_list
        utils/subset_data_dir.sh --spk-list $splitdir/spks_list $data $splitdir || exit 1;
    done

    echo "Decoding ${dataset}: $decode_dir"
    $cmd JOB=1:$nj $decode_dir/log/experiments.JOB.log \
        steps/run_experiments.sh ALL $configs/split${nj}/JOB.scp $data $pdfs $frames $model $graph $decode_dir

    ln -s `pwd`/$model/final.mdl $decode_dir/final.mdl
    for experiment in `ls -1 $decode_dir | grep -v log | grep -v final.mdl`; do
        time local/score_ted.sh --stm local/scoring/stms/ted.${dataset}.en-fr.en.norm.stm data/${dataset} data/lang/ $decode_dir/$experiment
    done

    echo
    echo "Best result $dataset"
    grep "Percent Total Error" $decode_dir/*/*/best_wer | sed 's/:.*= */ /;s/%.*/%/;' | sort -n -k2,2 | head -n 1
done;
