# Metagenome-assembly-and-phylogeny
Pipeline used to recover MAGs of the uncultured gammaproteobacterial from public metagenomes, and to place them in a Gammaproteobacteria species tree built from the GTDB bac120 marker genes.
# PIVX01 metagenome-assembled genomes and phylogeny

Pipeline used to recover MAGs of the uncultured gammaproteobacterial order
**PIVX01** (GTDB) from public metagenomes, and to place them in a
Gammaproteobacteria species tree built from the GTDB bac120 marker genes.

Metagenomes containing PIVX01 were identified with
[Sandpiper](https://sandpiper.qut.edu.au/taxonomy/o__PIVX01) and downloaded
from the SRA (accessions in [`samples.txt`](samples.txt)).

## Workflow

```
                 ┌──────────── per metagenome ─────────────┐
SRA ──► 01 download ──► 02 QC + trim ──► 03 assemble ──► 04 map + depth
                                                              │
        06 GTDB-Tk + Prokka ◄── 05 MetaBAT2 binning ◄─────────┘
                │  PIVX01 MAGs
                ▼
 GTDB reps ──► 07 select reps ──► 08 marker genes ──► 09 align/trim/concat ──► 10 tree
```

| Step | Script | Tools |
|------|--------|-------|
| 1 | `scripts/01_download.sh` | sra-tools (prefetch, fasterq-dump) |
| 2 | `scripts/02_qc_trim.sh` | FastQC, Trimmomatic |
| 3 | `scripts/03_assemble.sh` | MEGAHIT or metaSPAdes, seqtk (optional subsampling) |
| 4 | `scripts/04_map_depth.sh` | BBMap (bbwrap), samtools, `jgi_summarize_bam_contig_depths` |
| 5 | `scripts/05_bin.sh` | MetaBAT2 |
| 6 | `scripts/06_classify_annotate.sh` | GTDB-Tk, Prokka |
| 7 | `scripts/phylogeny/07_select_gtdb_reps.sh` | awk, GTDB r226 |
| 8 | `scripts/phylogeny/08_extract_markers.sh` | GTDB-Tk `identify` |
| 9 | `scripts/phylogeny/09_align_trim.sh` | MAFFT, trimAl, `utils/concat_alignments.pl` |
| 10 | `scripts/phylogeny/10_tree.sh` | IQ-TREE 3 (LG+C60+F+G) or FastTree |

## Setup

1. Edit the paths marked `EDIT ME` in [`config.sh`](config.sh). All scripts
   read their paths and parameters from there.
2. Module names (`module load ...`) follow our cluster; adjust them to yours.
3. Add `#SBATCH --partition / --nodelist / --account` lines as your cluster
   requires.
4. Run everything **from the repository root** (scripts use `./config.sh`
   and `utils/`).

## Usage

```bash
# 1. Download all metagenomes
sbatch scripts/01_download.sh samples.txt

# 2-6. Per-sample steps, chained with SLURM dependencies
for s in $(cat samples.txt); do
    j2=$(sbatch --parsable -J "$s" scripts/02_qc_trim.sh "$s")
    j3=$(sbatch --parsable -J "$s" -d afterok:$j2 scripts/03_assemble.sh "$s")   # add "spades" for metaSPAdes
    j4=$(sbatch --parsable -J "$s" -d afterok:$j3 scripts/04_map_depth.sh "$s")
    j5=$(sbatch --parsable -J "$s" -d afterok:$j4 scripts/05_bin.sh "$s")
         sbatch            -J "$s" -d afterok:$j5 scripts/06_classify_annotate.sh "$s"
done

# 7-10. Phylogeny
#   List the PIVX01 MAGs to include, one path per line:
cat samples/*/target_bins.txt   # check which bins were PIVX01
#   ...and write their paths into phylogeny/my_mags.txt, then:
bash   scripts/phylogeny/07_select_gtdb_reps.sh
sbatch scripts/phylogeny/08_extract_markers.sh
sbatch scripts/phylogeny/09_align_trim.sh
sbatch scripts/phylogeny/10_tree.sh fasttree   # quick check
sbatch scripts/phylogeny/10_tree.sh            # final IQ-TREE
```

### Sample-specific settings we used

| Sample | Notes |
|--------|-------|
| SRR23272269 | Too large to assemble whole: `SUBSAMPLE=0.4` |
| SRR28113953, SRR26146362 | Assembled with metaSPAdes (`spades`) |
| SRR6877521 | metaSPAdes failed; MEGAHIT with default k-mers worked |
| SRR26146362, SRR6877521 | Stricter trimming: `HEADCROP:10 LEADING:5 TRAILING:5 SLIDINGWINDOW:4:20 MINLEN:100` |
| SRR13054090 | No bins recovered by MetaBAT2 |

## Output layout

```
<PROJECT_DIR>/
├── raw_reads/              downloaded FASTQ
├── trimmed/                Trimmomatic output
├── fastqc/{raw,trimmed}/   QC reports
├── samples/<SRR>/
│   ├── assembly/           <SRR>.contigs.1k.fa
│   ├── mapping/            sorted BAM, depth table, bbmap stats
│   ├── bins/               MetaBAT2 MAGs
│   ├── gtdbtk/             GTDB-Tk classification
│   ├── annotation/         Prokka output for target MAGs
│   └── target_bins.txt     MAGs assigned to o__PIVX01
└── phylogeny/
    ├── genomes/            reference genomes + MAGs
    ├── markers/            GTDB-Tk single-copy markers
    ├── alignments/  trimmed/
    ├── concatenated.trimali (+ .partitions.nex, .occupancy.tsv)
    └── tree/
```

## Changes compared to the original lab notes

* `run_maffts_MinimumSeqs.pl` used `$nsq >> 4` (a bit-shift, true for
  any count ≥ 16) instead of `$nsq > 4`; fixed in `09_align_trim.sh`.
* Reads are mapped and sorted in one stream, so no multi-hundred-GB SAM
  files are written.
* Reference genomes are copied instead of symlinked, so the genome folder
  stays usable after moving it to another cluster.
* The concatenation script also writes a partition file and a per-genome
  gene-occupancy table, useful for spotting MAGs with too many missing markers.

## Citation of tools

Please cite the tools listed above (SRA Toolkit, FastQC, Trimmomatic, MEGAHIT,
SPAdes, BBMap, SAMtools, MetaBAT2, GTDB-Tk, Prokka, MAFFT, trimAl, IQ-TREE,
FastTree) and GTDB / Sandpiper if you use this pipeline.
