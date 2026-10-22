#!/bin/bash
#SBATCH --job-name=assembly
#SBATCH --partition=Main
#SBATCH --cpus-per-task=20
#SBATCH --mem=250G
#SBATCH --output=logs/assembly_%x_%j.out
#SBATCH --error=logs/assembly_%x_%j.err
# =============================================================================
# 03_assemble.sh — de novo metagenome assembly + contig length filter
#
# Usage:
#   sbatch scripts/03_assemble.sh SRR16133333              # MEGAHIT (default)
#   sbatch scripts/03_assemble.sh SRR28113953 spades       # metaSPAdes
#   SUBSAMPLE=0.4 sbatch scripts/03_assemble.sh SRR23272269
#       -> assemble a random 40% of read pairs (very large / memory-hungry runs)
#
# Input : ${TRIM_DIR}/<SAMPLE>_R{1,2}_paired.fq.gz
# Output: ${WORK_DIR}/<SAMPLE>/assembly/<SAMPLE>.contigs.1k.fa
#
# Notes from running this on our data:
#   * metaSPAdes generally gives better contiguity but needs a lot of RAM;
#     MEGAHIT is the fallback when SPAdes fails (e.g. SRR6877521).
#   * If MEGAHIT crashes on large k-mers, set MEGAHIT_KLIST="" in config.sh.
# =============================================================================
set -eo pipefail
source ./config.sh

SAMPLE="${1:?Usage: $0 <SAMPLE> [megahit|spades]}"
ASSEMBLER="${2:-megahit}"
OUT="${WORK_DIR}/${SAMPLE}/assembly"
mkdir -p "${WORK_DIR}/${SAMPLE}" "${OUT}"

R1="${TRIM_DIR}/${SAMPLE}_R1_paired.fq.gz"
R2="${TRIM_DIR}/${SAMPLE}_R2_paired.fq.gz"

# ---- Optional subsampling (seqtk, fixed seed for reproducibility) -----------
if [[ -n "${SUBSAMPLE}" ]]; then
    module load seqtk
    echo "Subsampling ${SUBSAMPLE} of the reads"
    seqtk sample -s100 "$R1" "${SUBSAMPLE}" | gzip > "${OUT}/${SAMPLE}_sub_R1.fq.gz"
    seqtk sample -s100 "$R2" "${SUBSAMPLE}" | gzip > "${OUT}/${SAMPLE}_sub_R2.fq.gz"
    R1="${OUT}/${SAMPLE}_sub_R1.fq.gz"
    R2="${OUT}/${SAMPLE}_sub_R2.fq.gz"
fi

# ---- Assembly ---------------------------------------------------------------
case "${ASSEMBLER}" in
  megahit)
    module load megahit
    KOPT=""
    [[ -n "${MEGAHIT_KLIST}" ]] && KOPT="--k-list ${MEGAHIT_KLIST}"
    # MEGAHIT refuses to write into an existing directory
    rm -rf "${OUT}/megahit"
    megahit -1 "$R1" -2 "$R2" ${KOPT} \
        --min-contig-len "${MIN_CONTIG_LEN}" \
        -t "${THREADS}" \
        --tmp-dir "${OUT}" \
        -o "${OUT}/megahit"
    RAW_CONTIGS="${OUT}/megahit/final.contigs.fa"
    ;;
  spades)
    module load spades
    spades.py --meta -1 "$R1" -2 "$R2" \
        -k "${SPADES_KLIST}" \
        -t "${THREADS}" -m "${SPADES_MEM_GB}" \
        -o "${OUT}/spades"
    RAW_CONTIGS="${OUT}/spades/contigs.fasta"
    ;;
  *)
    echo "Unknown assembler '${ASSEMBLER}' (use megahit or spades)"; exit 1 ;;
esac

# ---- Keep contigs >= MIN_CONTIG_LEN and simplify headers --------------------
# (MEGAHIT headers contain spaces, which break some downstream tools)
python3 utils/lenfilter.py "${RAW_CONTIGS}" "${OUT}/${SAMPLE}.contigs.1k.fa" "${MIN_CONTIG_LEN}"

# Assembly stats (BBTools)
module load bbmap
stats.sh "${OUT}/${SAMPLE}.contigs.1k.fa" > "${OUT}/${SAMPLE}.contigs.1k.stats.txt"
cat "${OUT}/${SAMPLE}.contigs.1k.stats.txt"
