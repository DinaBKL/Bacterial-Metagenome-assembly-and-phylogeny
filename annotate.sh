#!/bin/bash
#SBATCH --job-name=gtdbtk_prokka
#SBATCH --partition=Main
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --output=logs/classify_%x_%j.out
#SBATCH --error=logs/classify_%x_%j.err
# =============================================================================
# 06_classify_annotate.sh — taxonomy of all bins (GTDB-Tk), then annotation
#                           (Prokka) of the bins assigned to the target taxon
#
# Usage:
#   sbatch scripts/06_classify_annotate.sh SRR16133333
#   ANNOTATE_ALL=1 sbatch scripts/06_classify_annotate.sh SRR16133333
#       -> annotate every bin, not just ${TARGET_TAXON}
#
# Input : ${WORK_DIR}/<SAMPLE>/bins/*.fa
# Output: ${WORK_DIR}/<SAMPLE>/gtdbtk/gtdbtk.bac120.summary.tsv
#         ${WORK_DIR}/<SAMPLE>/annotation/<bin>/   (Prokka output)
#         ${WORK_DIR}/<SAMPLE>/target_bins.txt     (bins in TARGET_TAXON)
#
# Order of operations: classify first, pick the MAGs you care about, then
# annotate them (and run hmmsearch / eggNOG-mapper on their .faa files).
# Also consider CheckM2 for completeness/contamination before using MAGs.
# =============================================================================
set -eo pipefail
source ./config.sh
module load gtdbtk prokka

SAMPLE="${1:?Usage: $0 <SAMPLE>}"
S="${WORK_DIR}/${SAMPLE}"
mkdir -p "${S}/gtdbtk/scratch" "${S}/annotation"

# ---- 1. GTDB-Tk classification ---------------------------------------------
# --skip_ani_screen avoids needing the Mash/skani sketch database.
# --scratch_dir trades speed for lower RAM use during pplacer.
gtdbtk classify_wf \
    --genome_dir "${S}/bins" \
    --extension fa \
    --out_dir "${S}/gtdbtk" \
    --scratch_dir "${S}/gtdbtk/scratch" \
    --cpus "${THREADS}" \
    --skip_ani_screen

rm -rf "${S}/gtdbtk/scratch"
SUMMARY="${S}/gtdbtk/gtdbtk.bac120.summary.tsv"

# ---- 2. Pick bins to annotate -----------------------------------------------
if [[ -n "${ANNOTATE_ALL}" ]]; then
    ls "${S}/bins"/*.fa | xargs -n1 basename | sed 's/\.fa$//' > "${S}/target_bins.txt"
else
    # column 1 = genome name, column 2 = GTDB classification string
    awk -F'\t' -v t="${TARGET_TAXON}" 'NR>1 && index($2, t) {print $1}' \
        "${SUMMARY}" > "${S}/target_bins.txt"
fi
echo "Bins to annotate: $(wc -l < "${S}/target_bins.txt")"

# ---- 3. Prokka annotation ----------------------------------------------------
#   --compliant : GenBank-compliant names (also forces contig names <= 37 chars)
#   --locustag  : unique gene ID prefix per MAG
while read -r bin; do
    [[ -z "$bin" ]] && continue
    echo "[$(date +%T)] Annotating ${bin}"
    prokka "${S}/bins/${bin}.fa" \
        --outdir "${S}/annotation/${bin}" \
        --prefix "${bin}" \
        --locustag "$(echo "${bin}" | tr -cd '[:alnum:]' | tail -c 12)" \
        --strain "${bin}" \
        --kingdom Bacteria \
        --addgenes --addmrna --compliant --rfam \
        --centre DEEM \
        --cpus "${THREADS}" \
        --force
done < "${S}/target_bins.txt"

echo "Classification + annotation finished for ${SAMPLE}"
