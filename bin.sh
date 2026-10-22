#!/bin/bash
#SBATCH --job-name=metabat2
#SBATCH --partition=Main
#SBATCH --cpus-per-task=10
#SBATCH --mem=200G
#SBATCH --output=logs/metabat2_%x_%j.out
#SBATCH --error=logs/metabat2_%x_%j.err
# =============================================================================
# 05_bin.sh — bin contigs into MAGs with MetaBAT2
#
# Usage:
#   sbatch scripts/05_bin.sh SRR16133333
#
# Input : assembly/<SAMPLE>.contigs.1k.fa + mapping/<SAMPLE>.depth.txt
# Output: ${WORK_DIR}/<SAMPLE>/bins/<SAMPLE>.bin.<N>.fa
#         ${WORK_DIR}/<SAMPLE>/bins/unbinned/  (unbinned / lowDepth / tooShort)
#
# Note: with a single sample, MetaBAT2 bins on tetranucleotide frequency and
# one coverage value only, so some low-coverage metagenomes yield no bins
# (this happened with SRR13054090).
# =============================================================================
set -eo pipefail
source ./config.sh
module load metabat/2.18

SAMPLE="${1:?Usage: $0 <SAMPLE>}"
S="${WORK_DIR}/${SAMPLE}"
OUT="${S}/bins"
mkdir -p "${OUT}/unbinned"

#   -m        minimum contig length used for binning (MetaBAT2 minimum is 1500)
#   --unbinned  also write contigs that were not binned
metabat2 \
    -i "${S}/assembly/${SAMPLE}.contigs.1k.fa" \
    -a "${S}/mapping/${SAMPLE}.depth.txt" \
    -o "${OUT}/${SAMPLE}.bin" \
    -m "${METABAT_MIN_CONTIG}" \
    -t "${THREADS}" \
    --unbinned -v

# Move the leftover contig files out of the way so only real bins remain
mv "${OUT}"/*.unbinned.fa "${OUT}"/*.lowDepth.fa "${OUT}"/*.tooShort.fa \
   "${OUT}/unbinned/" 2>/dev/null || true

NBINS=$(ls "${OUT}"/*.fa 2>/dev/null | wc -l)
echo "${SAMPLE}: ${NBINS} bins"
