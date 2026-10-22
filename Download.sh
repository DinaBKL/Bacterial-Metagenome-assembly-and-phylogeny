#!/bin/bash
#SBATCH --job-name=sra_download
#SBATCH --partition=Main
#SBATCH --cpus-per-task=8
#SBATCH --output=logs/download_%j.out
#SBATCH --error=logs/download_%j.err
# =============================================================================
# 01_download.sh — download paired-end metagenomes from the SRA
#
# Usage:
#   sbatch scripts/01_download.sh SRR16133333 SRR23287147 ...
#   sbatch scripts/01_download.sh samples.txt          # one accession per line
#
# Output: ${RAW_DIR}/<SRR>_1.fastq.gz and <SRR>_2.fastq.gz
#
# Note: prefetch + fasterq-dump is much faster than plain `fastq-dump`.
# =============================================================================
set -eo pipefail
source ./config.sh
module load sra-tools/3.0.3

# Accept either a file of accessions or accessions as arguments
if [[ $# -eq 1 && -f "$1" ]]; then
    mapfile -t ACCESSIONS < "$1"
else
    ACCESSIONS=("$@")
fi
[[ ${#ACCESSIONS[@]} -gt 0 ]] || { echo "Usage: $0 SRR... | samples.txt"; exit 1; }

mkdir -p "${RAW_DIR}" && cd "${RAW_DIR}"

for acc in "${ACCESSIONS[@]}"; do
    [[ -z "$acc" ]] && continue
    if [[ -s "${acc}_1.fastq.gz" ]]; then
        echo "[skip] ${acc} already downloaded"
        continue
    fi
    echo "[$(date +%T)] Downloading ${acc}"
    prefetch --max-size u "${acc}"                        # fetch .sra (no size limit)
    fasterq-dump --split-files --threads "${THREADS}" \
                 --temp "${RAW_DIR}/tmp" "${acc}"         # -> _1.fastq / _2.fastq
    gzip "${acc}"_*.fastq                                 # use pigz if available
    rm -rf "${acc}"                                       # remove the .sra cache
done

echo "Done."
