#!/bin/bash
#SBATCH --job-name=qc_trim
#SBATCH --partition=Main
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/qc_trim_%x_%j.out
#SBATCH --error=logs/qc_trim_%x_%j.err
# =============================================================================
# 02_qc_trim.sh — FastQC on raw reads, then adapter/quality trimming
#
# Usage:
#   sbatch scripts/02_qc_trim.sh SRR16133333
#
# Input : ${RAW_DIR}/<SAMPLE>_1.fastq[.gz], <SAMPLE>_2.fastq[.gz]
# Output: ${TRIM_DIR}/<SAMPLE>_R{1,2}_paired.fq.gz   (used downstream)
#         ${TRIM_DIR}/<SAMPLE>_R{1,2}_unpaired.fq.gz (kept, not used)
#         ${QC_DIR}/  FastQC reports (raw + trimmed)
#
# Tip: inspect the raw FastQC "Overrepresented sequences" section; if adapters
# show up that are not in your adapter FASTA, add them to ${ADAPTERS}.
# For noisy runs override the trimming steps, e.g.:
#   TRIM_STEPS="HEADCROP:10 LEADING:5 TRAILING:5 SLIDINGWINDOW:4:20 MINLEN:100" \
#     sbatch scripts/02_qc_trim.sh SRR26146362
# =============================================================================
set -eo pipefail
source ./config.sh
module load fastqc/0.12.1
module load trimmomatic

SAMPLE="${1:?Usage: $0 <SAMPLE>}"
mkdir -p "${TRIM_DIR}" "${QC_DIR}/raw" "${QC_DIR}/trimmed"

# Find the raw reads (gzipped or not)
R1=$(ls "${RAW_DIR}/${SAMPLE}_1.fastq"* 2>/dev/null | head -1)
R2=$(ls "${RAW_DIR}/${SAMPLE}_2.fastq"* 2>/dev/null | head -1)
[[ -f "$R1" && -f "$R2" ]] || { echo "Reads for ${SAMPLE} not found in ${RAW_DIR}"; exit 1; }

# ---- 1. QC of raw reads -----------------------------------------------------
fastqc -t "${THREADS}" -o "${QC_DIR}/raw" "$R1" "$R2"

# ---- 2. Trimming ------------------------------------------------------------
# ILLUMINACLIP:<adapters>:<seed mismatches>:<palindrome clip>:<simple clip>
# Only added if the adapter file exists.
CLIP=""
[[ -f "${ADAPTERS}" ]] && CLIP="ILLUMINACLIP:${ADAPTERS}:2:30:10"

trimmomatic PE -threads "${THREADS}" \
    "$R1" "$R2" \
    "${TRIM_DIR}/${SAMPLE}_R1_paired.fq.gz" "${TRIM_DIR}/${SAMPLE}_R1_unpaired.fq.gz" \
    "${TRIM_DIR}/${SAMPLE}_R2_paired.fq.gz" "${TRIM_DIR}/${SAMPLE}_R2_unpaired.fq.gz" \
    ${CLIP} ${TRIM_STEPS}

# ---- 3. QC of trimmed reads -------------------------------------------------
fastqc -t "${THREADS}" -o "${QC_DIR}/trimmed" \
    "${TRIM_DIR}/${SAMPLE}_R1_paired.fq.gz" "${TRIM_DIR}/${SAMPLE}_R2_paired.fq.gz"

echo "Trimming finished for ${SAMPLE}"
