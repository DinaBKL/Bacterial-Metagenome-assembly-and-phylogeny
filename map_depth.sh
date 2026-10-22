#!/bin/bash
#SBATCH --job-name=map_depth
#SBATCH --partition=Main
#SBATCH --cpus-per-task=16
#SBATCH --mem=200G
#SBATCH --output=logs/map_depth_%x_%j.out
#SBATCH --error=logs/map_depth_%x_%j.err
# =============================================================================
# 04_map_depth.sh — map reads back to contigs and compute per-contig depth
#
# Usage:
#   sbatch scripts/04_map_depth.sh SRR16133333
#
# Input : ${WORK_DIR}/<SAMPLE>/assembly/<SAMPLE>.contigs.1k.fa
#         ${TRIM_DIR}/<SAMPLE>_R{1,2}_paired.fq.gz
# Output: ${WORK_DIR}/<SAMPLE>/mapping/<SAMPLE>.sorted.bam (+ .bai)
#         ${WORK_DIR}/<SAMPLE>/mapping/<SAMPLE>.depth.txt   (MetaBAT2 input)
#         ${WORK_DIR}/<SAMPLE>/mapping/{stats,rpkm}/        (bbmap reports)
#
# The SAM is streamed straight into samtools, so no huge .sam file is ever
# written to disk (this was the source of earlier "out of space" failures).
# =============================================================================
set -eo pipefail
source ./config.sh
module load bbmap samtools metabat

SAMPLE="${1:?Usage: $0 <SAMPLE>}"
CONTIGS="${WORK_DIR}/${SAMPLE}/assembly/${SAMPLE}.contigs.1k.fa"
OUT="${WORK_DIR}/${SAMPLE}/mapping"
mkdir -p "${OUT}/stats" "${OUT}/rpkm" "${OUT}/tmp"

R1="${TRIM_DIR}/${SAMPLE}_R1_paired.fq.gz"
R2="${TRIM_DIR}/${SAMPLE}_R2_paired.fq.gz"

# ---- 1. Map reads (BBMap) -> filter unmapped -> sort ------------------------
#   nodisk      : build the index in memory only
#   fast        : faster, slightly less sensitive mode
#   kfilter=31  : require >=31 consecutive matching bases
#   subfilter=15: discard alignments with >15 substitutions
#   maxindel=80 : max indel length allowed
bbwrap.sh ref="${CONTIGS}" nodisk fast=t \
    in1="$R1" in2="$R2" \
    out=stdout.sam \
    kfilter=31 subfilter=15 maxindel=80 \
    threads="${THREADS}" \
    rpkm="${OUT}/rpkm/${SAMPLE}.rpkm.txt" \
    scafstats="${OUT}/stats/${SAMPLE}.scafstats.txt" \
    covstats="${OUT}/stats/${SAMPLE}.covstats.txt" \
  | samtools view -b -F 4 --threads 4 - \
  | samtools sort -T "${OUT}/tmp/${SAMPLE}" -m 2G --threads 4 \
        -o "${OUT}/${SAMPLE}.sorted.bam" -

samtools index "${OUT}/${SAMPLE}.sorted.bam"
samtools quickcheck "${OUT}/${SAMPLE}.sorted.bam" && echo "BAM OK"
rm -rf "${OUT}/tmp"

# ---- 2. Per-contig depth for MetaBAT2 ---------------------------------------
jgi_summarize_bam_contig_depths \
    --outputDepth "${OUT}/${SAMPLE}.depth.txt" \
    --referenceFasta "${CONTIGS}" \
    "${OUT}/${SAMPLE}.sorted.bam"

# Two-column abundance table (contig, mean depth) — useful for MaxBin2 etc.
awk 'NR>1 {print $1"\t"$4}' "${OUT}/${SAMPLE}.depth.txt" > "${OUT}/${SAMPLE}.abundance.txt"

echo "Mapping + depth finished for ${SAMPLE}"
