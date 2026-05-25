#!/usr/bin/env bash
# plantbench.sh — PlantBench TUI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLANTBENCH_DIR="${SCRIPT_DIR}/plantbench"

# ─── Terminal setup / teardown ────────────────────────────────────────────────

cleanup() {
    printf '\033[?25h'    # restore cursor
    printf '\033[?1049l'  # restore normal screen buffer
    stty echo 2>/dev/null || true
}
trap cleanup EXIT INT TERM

printf '\033[?1049h'  # alternate screen buffer
printf '\033[?25l'    # hide cursor
stty -echo

COLS=$(tput cols)
LINES=$(tput lines)

# ─── Drawing primitives ───────────────────────────────────────────────────────

move()          { printf '\033[%d;%dH' "$1" "$2"; }
clear_screen()  { printf '\033[2J'; }
show_cursor()   { printf '\033[?25h'; }
hide_cursor()   { printf '\033[?25l'; }

repeat_into() {
    local _var="$1" _str="$2" _n="$3" _out="" i
    for (( i = 0; i < _n; i++ )); do _out+="${_str}"; done
    printf -v "${_var}" '%s' "${_out}"
}

# draw_box  top  left  height  width
draw_box() {
    local top="$1" left="$2" h="$3" w="$4"
    local bottom=$(( top + h - 1 )) right=$(( left + w - 1 )) inner=$(( w - 2 ))
    local hbar; repeat_into hbar "─" "${inner}"
    move "${top}"    "${left}"; printf '┌%s┐' "${hbar}"
    move "${bottom}" "${left}"; printf '└%s┘' "${hbar}"
    local r
    for (( r = top + 1; r < bottom; r++ )); do
        move "${r}" "${left}";  printf '│'
        move "${r}" "${right}"; printf '│'
    done
}

# draw_round_box  top  left  height  width
# Same as draw_box, but with rounded corners for smaller callout panels.
draw_round_box() {
    local top="$1" left="$2" h="$3" w="$4"
    local bottom=$(( top + h - 1 )) right=$(( left + w - 1 )) inner=$(( w - 2 ))
    local hbar; repeat_into hbar "─" "${inner}"
    move "${top}"    "${left}"; printf '╭%s╮' "${hbar}"
    move "${bottom}" "${left}"; printf '╰%s╯' "${hbar}"
    local r
    for (( r = top + 1; r < bottom; r++ )); do
        move "${r}" "${left}";  printf '│'
        move "${r}" "${right}"; printf '│'
    done
}

# draw_outer_frame — full-terminal border.
# Temporarily disables autowrap while drawing the final bottom-right corner.
# Printing in the terminal's last cell can otherwise auto-scroll in many terminals.
draw_outer_frame() {
    local inner=$(( COLS - 2 ))
    local hbar; repeat_into hbar "─" "${inner}"
    move 1          1;          printf '┌%s┐' "${hbar}"
    move "${LINES}" 1;          printf '└%s'  "${hbar}"
    printf '[?7l'
    move "${LINES}" "${COLS}"; printf '┘'
    printf '[?7h'
    local r
    for (( r = 2; r < LINES; r++ )); do
        move "${r}" 1;           printf '│'
        move "${r}" "${COLS}";   printf '│'
    done
}

# draw_hline  row  left  width   (mid-box separator: ├──┤)
draw_hline() {
    local inner=$(( $3 - 2 ))
    local hbar; repeat_into hbar "─" "${inner}"
    move "$1" "$2"; printf '├%s┤' "${hbar}"
}

print_clipped() {
    local width="$1" text="$2"
    printf '%.*s' "${width}" "${text}"
}

setup_box_width() {
    local preferred="${1:-100}"
    local w=$(( COLS - 8 ))
    (( w > preferred )) && w="${preferred}"
    (( w < 60 )) && w=60
    (( w > COLS - 4 )) && w=$(( COLS - 4 ))
    printf '%d' "${w}"
}

# ─── Key reading ──────────────────────────────────────────────────────────────

KEY=""
KEY_TIMEOUT=1
read_key() {
    KEY=""
    KEY_TIMEOUT=1
    local rest=""
    IFS= read -rsn1 -t 0.05 KEY && KEY_TIMEOUT=0 || true
    if [[ "${KEY_TIMEOUT}" == 0 && "${KEY}" == $'\033' ]]; then
        IFS= read -rsn2 -t 0.05 rest || true
        KEY+="${rest}"
    fi
}

# ─── Install detection ────────────────────────────────────────────────────────

detect_install() { [[ -d "${PLANTBENCH_DIR}/weights" ]]; }

# Prints "ModelName  size1 · size2 · size3" lines from weights/
get_model_lines() {
    local weights_dir="${PLANTBENCH_DIR}/weights"
    [[ -d "${weights_dir}" ]] || return
    local model_dir sizes size_list
    for model_dir in "${weights_dir}"/*/; do
        [[ -d "${model_dir}" ]] || continue
        local model_name; model_name="$(basename "${model_dir}")"
        size_list=""
        for size_dir in "${model_dir}"/*/; do
            [[ -d "${size_dir}" ]] || continue
            local s; s="$(basename "${size_dir}")"
            [[ -z "${size_list}" ]] && size_list="${s}" || size_list+=" · ${s}"
        done
        [[ -z "${size_list}" ]] && size_list="(no sizes found)"
        printf '%s\t%s\n' "${model_name}" "${size_list}"
    done
}

# ─── Setup data ───────────────────────────────────────────────────────────────

SINGLE_SIZE_MODELS=("2" "6")

declare -A MODEL_NAMES=(
    [1]="Evo2"
    [2]="AgroNT"
    [3]="PlantCAD2"
    [4]="NTv3"
    [5]="GENERator"
    [6]="DNABERT-2"
)

declare -A MODEL_SIZES=(
    [1]="Small (1b)|Medium (7b)|Large (20b)"
    [2]="1b"
    [3]="Small (88M)|Medium (311M)|Large (694M)"
    [4]="Small (7.69M)|Medium (100M)|Large (650M)"
    [5]="Small (1.2B eukaryote)|Large (3B eukaryote)"
    [6]="117M"
)

declare -A MODEL_INFO_TITLE=(
    [1]="Evo2 — Arc Institute / NVIDIA"
    [2]="AgroNT — InstaDeep"
    [3]="PlantCAD2 — Kuleshov Group"
    [4]="NTv3 — InstaDeep"
    [5]="GENERator — GenerTeam"
    [6]="DNABERT-2 — MAGICS-LAB"
)

declare -A MODEL_INFO_DATE=(
    [1]="February 19 · 2025"
    [2]="July 9 · 2024"
    [3]="September 1 · 2025"
    [4]="December 25 · 2025"
    [5]="February 11 · 2025"
    [6]="June 26 · 2023"
)

declare -A MODEL_INFO_BODY=(
    [1]="Generalist DNA foundation model for prediction and design across DNA, RNA, and proteins; trained on trillions of nucleotides with long-context single-base modeling."
    [2]="Plant-focused nucleotide transformer trained on 48 plant genomes, emphasizing crop and edible plant species for regulatory and gene-expression prediction tasks."
    [3]="Angiosperm-focused long-context DNA language model for cross-species functional annotation, including gene expression and chromatin-accessibility style tasks."
    [4]="Multi-species genomics foundation model family for long-range sequence-to-function modeling, genome annotation, and controllable regulatory sequence design."
    [5]="Long-context generative genomic foundation model trained on eukaryotic DNA; designed for sequence generation and broad genomic benchmark performance."
    [6]="Efficient multi-species genome foundation model using BPE tokenization and ALiBi; introduced with the Genome Understanding Evaluation benchmark."
)

declare -A REPO_MAP=(
    [1]="https://github.com/NVIDIA/bionemo-framework.git"
    [2]="https://github.com/instadeepai/nucleotide-transformer.git"
    [3]="https://github.com/plantcad/plantcad.git"
    [4]="https://github.com/instadeepai/nucleotide-transformer.git"
    [5]="https://github.com/GenerTeam/GENERator.git"
    [6]="https://github.com/MAGICS-LAB/DNABERT_2.git"
)

declare -A REPO_DIR_MAP=(
    ["https://github.com/NVIDIA/bionemo-framework.git"]="bionemo-framework"
    ["https://github.com/instadeepai/nucleotide-transformer.git"]="nucleotide-transformer"
    ["https://github.com/plantcad/plantcad.git"]="plantcad"
    ["https://github.com/GenerTeam/GENERator.git"]="GENERator"
    ["https://github.com/MAGICS-LAB/DNABERT_2.git"]="DNABERT_2"
)

declare -A CONTAINER_MAP=(
    [1]="oras://ghcr.io/caleblx/bionemo_evo2:latest"
    [2]="oras://ghcr.io/caleblx/agront:latest"
    [3]="oras://ghcr.io/caleblx/plantcad2:latest"
    [4]="oras://ghcr.io/caleblx/ntv3:latest"
    [5]="oras://ghcr.io/caleblx/generator:latest"
    [6]="oras://ghcr.io/caleblx/dnabert2:latest"
)

declare -A CONTAINER_FILE_MAP=(
    [1]="bionemo_evo2.sif"
    [2]="agront.sif"
    [3]="plantcad2.sif"
    [4]="ntv3.sif"
    [5]="generator.sif"
    [6]="dnabert2.sif"
)

declare -A WEIGHT_MAP=(
    ["1|Small (1b)"]="arcinstitute/evo2_1b_base|1b"
    ["1|Medium (7b)"]="arcinstitute/evo2_7b|7b"
    ["1|Large (20b)"]="arcinstitute/evo2_20b|20b"
    ["2|1b"]="InstaDeepAI/agro-nucleotide-transformer-1b|1b"
    ["3|Small (88M)"]="kuleshov-group/PlantCAD2-Small-l24-d0768|Small"
    ["3|Medium (311M)"]="kuleshov-group/PlantCAD2-Medium-l48-d1024|Medium"
    ["3|Large (694M)"]="kuleshov-group/PlantCAD2-Large-l48-d1536|Large"
    ["4|Small (7.69M)"]="InstaDeepAI/NTv3_8M_pre|Small"
    ["4|Medium (100M)"]="InstaDeepAI/NTv3_100M_pre|Medium"
    ["4|Large (650M)"]="InstaDeepAI/NTv3_650M_pre|Large"
    ["5|Small (1.2B eukaryote)"]="GenerTeam/GENERator-eukaryote-1.2b-base|Small_1.2b"
    ["5|Large (3B eukaryote)"]="GenerTeam/GENERator-eukaryote-3b-base|Large_3b"
    ["6|117M"]="zhihan1996/DNABERT-2-117M|117M"
)

# ─── State ────────────────────────────────────────────────────────────────────

STATE="home"        # home | manual_input | setup_* states
MENU_IDX=0
MANUAL_INPUT=""
MANUAL_ERR=""
ANIM_TICK=0
INFO_LINE1='🌿 Code implementation for the paper'
INFO_TEXT='Deep Learning Genome-to-Expression Models for Plants: Benchmarking New Opportunities'
WRAPPED_LINES=()

NO_INSTALL_MENU=(
    "Run setup"
    "Select an existing installation"
    "Quit"
)

MAIN_MENU_IDX=0
MAIN_STUB_TITLE=""
MAIN_MENU=(
    "Evaluate on example FASTA"
    "Evaluate on custom FASTA"
    "Add or remove models"
    "Select a different installation"
    "Quit"
)

CUDA_VERSION=""
SETUP_SAVE_INPUT=""
SETUP_EXISTING_MENU_IDX=0
SETUP_SAVE_DIR=""
SETUP_PLANTBENCH_DIR=""
SETUP_ERR=""
SETUP_LOG=()
SETUP_VIEW_MODE="status"
SETUP_RUNNING_SCREEN_DRAWN=0
SETUP_CURRENT_MODEL=0
SETUP_CURRENT_STEP=""
SETUP_SPINNER_FRAME=0
declare -A SETUP_MODEL_RUN_STATUS=()
declare -A SETUP_STEP_RUN_STATUS=()
declare -A SETUP_WEIGHT_SIZE_RUN_STATUS=()
SETUP_MODE="install"
SETUP_PATH_LABEL_MODE="installation"
SETUP_COMMAND_LOG="${TMPDIR:-/tmp}/plantbench_setup_$$.log"
SETUP_MENU_IDX=0
SETUP_SIZE_STAGE=0
SIZE_MENU_IDX=0
SELECTED_MODELS=()
MULTI_SIZE_SELECTED=()
declare -A SETUP_MODEL_SELECTED=()
declare -A SETUP_SIZE_SELECTED=()
declare -A SELECTED_SIZES=()

# ─── General helpers ──────────────────────────────────────────────────────────

contains_single_size_model() {
    local model_idx="$1" m
    for m in "${SINGLE_SIZE_MODELS[@]}"; do
        [[ "${m}" == "${model_idx}" ]] && return 0
    done
    return 1
}

format_size_entry() {
    local size_entry="$1" size_label size_value
    if [[ "${size_entry}" =~ ^([^[:space:]]+)[[:space:]]+\((.*)\)$ ]]; then
        size_label="${BASH_REMATCH[1]}"
        size_value="${BASH_REMATCH[2]}"
        printf '%s >>> %s' "${size_label}" "${size_value}"
    else
        printf 'Default >>> %s' "${size_entry}"
    fi
}

size_short_label() {
    local size_entry="$1"
    if [[ "${size_entry}" =~ ^([^[:space:]]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf '%s' "${size_entry}"
    fi
}

join_by_comma() {
    local out="" item
    for item in "$@"; do
        [[ -z "${out}" ]] && out="${item}" || out+=", ${item}"
    done
    printf '%s' "${out}"
}

is_size_selected() {
    local model_idx="$1" size_entry="$2"
    local selected="${SELECTED_SIZES[$model_idx]:-}"
    [[ "|${selected}|" == *"|${size_entry}|"* ]]
}

model_size_dir_label() {
    local model_idx="$1" size_entry="$2"
    local map_key="${model_idx}|${size_entry}" dir_label

    [[ -n "${WEIGHT_MAP[$map_key]+x}" ]] || return 1
    IFS='|' read -r _ dir_label <<< "${WEIGHT_MAP[$map_key]}"
    printf '%s' "${dir_label}"
}

model_size_installed() {
    local model_idx="$1" size_entry="$2" dir_label

    dir_label="$(model_size_dir_label "${model_idx}" "${size_entry}")" || return 1
    [[ -d "${SETUP_PLANTBENCH_DIR}/weights/${MODEL_NAMES[$model_idx]}/${dir_label}" ]]
}

model_any_size_installed() {
    local model_idx="$1" size_entry
    local -a size_options=()

    IFS='|' read -ra size_options <<< "${MODEL_SIZES[$model_idx]}"
    for size_entry in "${size_options[@]}"; do
        model_size_installed "${model_idx}" "${size_entry}" && return 0
    done
    return 1
}

model_has_selected_payload() {
    local model_idx="$1"

    [[ "${SETUP_MODEL_SELECTED[$model_idx]:-0}" == "1" ]] || return 1
    if contains_single_size_model "${model_idx}"; then
        [[ "${SETUP_MODE}" != "modify" ]] && return 0
        [[ -n "${SELECTED_SIZES[$model_idx]:-}" ]]
        return
    fi
    [[ -n "${SELECTED_SIZES[$model_idx]:-}" ]]
}

setup_seed_modify_selection() {
    local i
    for (( i = 1; i <= 6; i++ )); do
        if model_any_size_installed "${i}"; then
            SETUP_MODEL_SELECTED[$i]=1
        else
            SETUP_MODEL_SELECTED[$i]=0
        fi
    done
}

current_size_selection_removes_installed() {
    [[ "${SETUP_MODE}" == "modify" ]] || return 1
    (( ${#MULTI_SIZE_SELECTED[@]} > 0 )) || return 1

    local m="${MULTI_SIZE_SELECTED[$SETUP_SIZE_STAGE]}"
    local -a sizes=()
    local i size_entry
    IFS='|' read -ra sizes <<< "${MODEL_SIZES[$m]}"

    for i in "${!sizes[@]}"; do
        size_entry="${sizes[$i]}"
        if model_size_installed "${m}" "${size_entry}" && [[ "${SETUP_SIZE_SELECTED["${m}|${i}"]:-0}" != "1" ]]; then
            return 0
        fi
    done
    return 1
}

modify_has_model_removal_pending() {
    [[ "${SETUP_MODE}" == "modify" ]] || return 1

    local i
    for (( i = 1; i <= 6; i++ )); do
        if model_any_size_installed "${i}" && [[ "${SETUP_MODEL_SELECTED[$i]:-0}" != "1" ]]; then
            return 0
        fi
    done
    return 1
}

wrap_text_for_box() {
    local text="$1" width="$2"
    WRAPPED_LINES=()

    local line="" word
    local -a words=()
    read -r -a words <<< "${text}"

    for word in "${words[@]}"; do
        if [[ -z "${line}" ]]; then
            line="${word}"
        elif (( ${#line} + 1 + ${#word} <= width )); then
            line+=" ${word}"
        else
            WRAPPED_LINES+=("${line}")
            line="${word}"
        fi
    done

    [[ -n "${line}" ]] && WRAPPED_LINES+=("${line}")
}

info_box_height_for_width() {
    local box_w="$1"
    local content_w=$(( box_w - 4 ))
    wrap_text_for_box "${INFO_TEXT}" "${content_w}"
    printf '%d' $(( ${#WRAPPED_LINES[@]} + 4 ))
}

# ─── Setup workflow helpers ───────────────────────────────────────────────────

reset_setup_state() {
    local i
    SETUP_SAVE_INPUT=""
    SETUP_EXISTING_MENU_IDX=0
    SETUP_SAVE_DIR=""
    SETUP_PLANTBENCH_DIR=""
    SETUP_ERR=""
    SETUP_LOG=()
    SETUP_PATH_LABEL_MODE="installation"
    SETUP_MENU_IDX=0
    SETUP_SIZE_STAGE=0
    SIZE_MENU_IDX=0
    SELECTED_MODELS=()
    MULTI_SIZE_SELECTED=()
    SETUP_MODEL_SELECTED=()
    SETUP_SIZE_SELECTED=()
    SELECTED_SIZES=()
    for (( i = 1; i <= 6; i++ )); do
        SETUP_MODEL_SELECTED[$i]=0
    done
    : > "${SETUP_COMMAND_LOG}"
}

setup_check_dependencies() {
    CUDA_VERSION="$(module list 2>&1 | sed -nE 's/.*cuda\/([0-9]+\.[0-9]+).*/\1/p' | tail -n 1 || true)"

    if [[ -z "${CUDA_VERSION}" ]]; then
        SETUP_ERR="Dependency check failed: no CUDA module loaded. Please run: module load cuda/12.8"
        return 1
    fi

    if [[ "${CUDA_VERSION}" != "12.8" ]]; then
        SETUP_ERR="Dependency check failed: CUDA 12.8 is required but found ${CUDA_VERSION}. Please run: module load cuda/12.8"
        return 1
    fi

    if ! command -v apptainer >/dev/null 2>&1; then
        SETUP_ERR="Dependency check failed: apptainer was not found in PATH. Please install/load apptainer and try again."
        return 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        SETUP_ERR="Dependency check failed: git was not found in PATH. Please install/load git and try again."
        return 1
    fi

    if ! command -v hf >/dev/null 2>&1; then
        SETUP_ERR="Dependency check failed: Hugging Face CLI 'hf' was not found in PATH. Please install/load huggingface_hub and try again."
        return 1
    fi

    return 0
}

start_setup() {
    reset_setup_state
    SETUP_MODE="install"
    SETUP_PATH_LABEL_MODE="selected"
    if setup_check_dependencies; then
        STATE="setup_save_dir"
    else
        STATE="setup_error"
    fi
}

start_modify_setup() {
    reset_setup_state
    SETUP_MODE="modify"
    SETUP_PATH_LABEL_MODE="installation"
    SETUP_SAVE_DIR="$(dirname "${PLANTBENCH_DIR}")"
    SETUP_PLANTBENCH_DIR="${PLANTBENCH_DIR}"
    if setup_check_dependencies; then
        STATE="setup_models"
        SETUP_MENU_IDX=0
    else
        STATE="setup_error"
    fi
}

setup_apply_save_dir() {
    local save_dir="${SETUP_SAVE_INPUT:-${SCRIPT_DIR}}"
    save_dir="${save_dir/#\~/$HOME}"
    [[ "${save_dir}" == "share" ]] && save_dir="${HOME}/hpc-share"

    SETUP_SAVE_DIR="${save_dir}"
    SETUP_PLANTBENCH_DIR="${SETUP_SAVE_DIR}/plantbench"
    SETUP_ERR=""
    SETUP_MENU_IDX=0

    if [[ -d "${SETUP_PLANTBENCH_DIR}" ]]; then
        SETUP_EXISTING_MENU_IDX=0
        STATE="setup_existing_install"
    else
        STATE="setup_models"
    fi
}

build_selected_models() {
    local i
    SELECTED_MODELS=()
    for (( i = 1; i <= 6; i++ )); do
        if [[ "${SETUP_MODEL_SELECTED[$i]:-0}" == "1" ]]; then
            SELECTED_MODELS+=("${i}")
        fi
    done
}

setup_prepare_size_flow() {
    local m i
    MULTI_SIZE_SELECTED=()
    SELECTED_SIZES=()
    SETUP_SIZE_SELECTED=()

    for m in "${SELECTED_MODELS[@]}"; do
        if contains_single_size_model "${m}" && [[ "${SETUP_MODE}" != "modify" ]]; then
            SELECTED_SIZES[$m]="all"
        else
            MULTI_SIZE_SELECTED+=("${m}")
            IFS='|' read -ra sizes <<< "${MODEL_SIZES[$m]}"
            for i in "${!sizes[@]}"; do
                if [[ "${SETUP_MODE}" == "modify" ]] && model_size_installed "${m}" "${sizes[$i]}"; then
                    SETUP_SIZE_SELECTED["${m}|${i}"]=1
                else
                    SETUP_SIZE_SELECTED["${m}|${i}"]=0
                fi
            done
        fi
    done

    SETUP_SIZE_STAGE=0
    SIZE_MENU_IDX=0
    SETUP_ERR=""

    if (( ${#MULTI_SIZE_SELECTED[@]} == 0 )); then
        STATE="setup_confirm"
    else
        STATE="setup_sizes"
    fi
}

setup_commit_current_sizes() {
    local m="${MULTI_SIZE_SELECTED[$SETUP_SIZE_STAGE]}"
    local -a sizes selected=()
    local i joined=""
    IFS='|' read -ra sizes <<< "${MODEL_SIZES[$m]}"

    for i in "${!sizes[@]}"; do
        if [[ "${SETUP_SIZE_SELECTED["${m}|${i}"]:-0}" == "1" ]]; then
            selected+=("${sizes[$i]}")
        fi
    done

    if (( ${#selected[@]} == 0 )); then
        if [[ "${SETUP_MODE}" == "modify" ]]; then
            SELECTED_SIZES[$m]=""
            SETUP_ERR=""
            return 0
        fi
        SETUP_ERR="Select at least one size for ${MODEL_NAMES[$m]}."
        return 1
    fi

    for i in "${!selected[@]}"; do
        [[ -z "${joined}" ]] && joined="${selected[$i]}" || joined+="|${selected[$i]}"
    done
    SELECTED_SIZES[$m]="${joined}"
    SETUP_ERR=""
    return 0
}

setup_toggle_all_models() {
    local i any_unselected=0
    for (( i = 1; i <= 6; i++ )); do
        [[ "${SETUP_MODEL_SELECTED[$i]:-0}" == "0" ]] && any_unselected=1
    done
    for (( i = 1; i <= 6; i++ )); do
        SETUP_MODEL_SELECTED[$i]="${any_unselected}"
    done
}

setup_toggle_all_sizes_for_current_model() {
    local m="${MULTI_SIZE_SELECTED[$SETUP_SIZE_STAGE]}"
    local -a sizes
    local i any_unselected=0
    IFS='|' read -ra sizes <<< "${MODEL_SIZES[$m]}"

    for i in "${!sizes[@]}"; do
        [[ "${SETUP_SIZE_SELECTED["${m}|${i}"]:-0}" == "0" ]] && any_unselected=1
    done
    for i in "${!sizes[@]}"; do
        SETUP_SIZE_SELECTED["${m}|${i}"]="${any_unselected}"
    done
}

selected_size_summary() {
    local m="$1"
    local -a labels=()
    local -a sizes
    local size_entry

    if contains_single_size_model "${m}"; then
        printf 'Default (%s)' "${MODEL_SIZES[$m]}"
        return
    fi

    IFS='|' read -ra sizes <<< "${MODEL_SIZES[$m]}"
    for size_entry in "${sizes[@]}"; do
        if is_size_selected "${m}" "${size_entry}"; then
            labels+=("$(size_short_label "${size_entry}")")
        fi
    done

    if (( ${#labels[@]} == 0 )); then
        printf '(none)'
    else
        join_by_comma "${labels[@]}"
    fi
}

setup_init_running_progress() {
    SETUP_MODEL_RUN_STATUS=()
    SETUP_STEP_RUN_STATUS=()
    SETUP_WEIGHT_SIZE_RUN_STATUS=()
    SETUP_CURRENT_MODEL=0
    SETUP_CURRENT_STEP=""
    SETUP_SPINNER_FRAME=0
    SETUP_RUNNING_SCREEN_DRAWN=0
    SETUP_VIEW_MODE="status"

    local m step size_entry
    for m in "${SELECTED_MODELS[@]}"; do
        SETUP_MODEL_RUN_STATUS[$m]="pending"
        for step in "Pulling container" "Cloning repo" "Downloading model weights"; do
            SETUP_STEP_RUN_STATUS["${m}|${step}"]="pending"
        done
        IFS='|' read -ra size_options <<< "${MODEL_SIZES[$m]}"
        for size_entry in "${size_options[@]}"; do
            SETUP_WEIGHT_SIZE_RUN_STATUS["${m}|${size_entry}"]="pending"
        done
    done
}

setup_set_model_current() {
    local m="$1"
    SETUP_CURRENT_MODEL="${m}"
    SETUP_CURRENT_STEP=""
    SETUP_MODEL_RUN_STATUS[$m]="current"
    render_setup_running_status_only
}

setup_set_step_status() {
    local m="$1" step="$2" status="$3"
    SETUP_STEP_RUN_STATUS["${m}|${step}"]="${status}"
}

setup_set_step_current() {
    local m="$1" step="$2"
    SETUP_CURRENT_MODEL="${m}"
    SETUP_CURRENT_STEP="${step}"
    SETUP_MODEL_RUN_STATUS[$m]="current"
    setup_set_step_status "${m}" "${step}" "current"
    render_setup_running_status_only
}

setup_finish_step() {
    local m="$1" step="$2" status="${3:-done}"
    setup_set_step_status "${m}" "${step}" "${status}"
    render_setup_running_status_only
}

setup_set_weight_size_status() {
    local m="$1" size_entry="$2" status="$3"
    SETUP_WEIGHT_SIZE_RUN_STATUS["${m}|${size_entry}"]="${status}"
}

setup_set_weight_size_current() {
    local m="$1" size_entry="$2"
    setup_set_weight_size_status "${m}" "${size_entry}" "current"
    render_setup_running_status_only
}

setup_finish_weight_size() {
    local m="$1" size_entry="$2" status="${3:-done}"
    setup_set_weight_size_status "${m}" "${size_entry}" "${status}"
    render_setup_running_status_only
}

setup_finish_model() {
    local m="$1"
    SETUP_MODEL_RUN_STATUS[$m]="done"
    SETUP_CURRENT_STEP=""
    render_setup_running_status_only
}

setup_running_current_spinner_row() {
    local __row_var="$1"

    local G_W G_H G_T G_L
    setup_running_geometry G

    local row=$(( G_T + 7 ))
    local m model_status step step_status size_entry
    local -a size_options=()

    for m in "${SELECTED_MODELS[@]}"; do
        model_status="${SETUP_MODEL_RUN_STATUS[$m]:-pending}"

        if [[ "${model_status}" == "current" ]]; then
            printf -v "${__row_var}" '%d' "${row}"
            return 0
        fi

        (( row++ ))

        if [[ "${model_status}" == "current" ]]; then
            for step in "Pulling container" "Cloning repo" "Downloading model weights"; do
                (( row++ ))
                if [[ "${step}" == "Downloading model weights" && "${SETUP_CURRENT_STEP}" == "Downloading model weights" ]]; then
                    IFS='|' read -ra size_options <<< "${MODEL_SIZES[$m]}"
                    for size_entry in "${size_options[@]}"; do
                        if [[ -n "${SETUP_WEIGHT_SIZE_RUN_STATUS["${m}|${size_entry}"]:-}" ]]; then
                            (( row++ ))
                        fi
                    done
                fi
            done
            (( row++ ))
        fi
    done

    return 1
}

render_setup_running_spinner_only() {
    [[ "${STATE}" == "setup_running" ]] || return
    [[ "${SETUP_VIEW_MODE}" == "status" ]] || return
    (( SETUP_RUNNING_SCREEN_DRAWN == 1 )) || return

    local G_W G_H G_T G_L
    setup_running_geometry G

    local spinner_row
    setup_running_current_spinner_row spinner_row || return

    local right_col=$(( G_L + G_W - 6 ))
    move "${spinner_row}" "${right_col}"
    printf '%s' "$(setup_spinner_char)"
    hide_cursor
}

setup_step_display_label() {
    local step="$1" status="$2"

    case "${step}" in
        "Pulling container")
            case "${status}" in
                current) printf 'Pulling container' ;;
                done)    printf 'Pulled container' ;;
                *)       printf 'Pull container' ;;
            esac
            ;;
        "Cloning repo")
            case "${status}" in
                current) printf 'Cloning repo' ;;
                done)    printf 'Cloned repo' ;;
                *)       printf 'Clone repo' ;;
            esac
            ;;
        "Downloading model weights")
            case "${status}" in
                current) printf 'Downloading model weights' ;;
                done)    printf 'Downloaded model weights' ;;
                *)       printf 'Download model weights' ;;
            esac
            ;;
        *)
            printf '%s' "${step}"
            ;;
    esac
}

setup_spinner_char() {
    local frames=( "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏" )
    printf '%s' "${frames[$(( SETUP_SPINNER_FRAME % ${#frames[@]} ))]}"
}

setup_toggle_running_view() {
    if [[ "${SETUP_VIEW_MODE}" == "logs" ]]; then
        SETUP_VIEW_MODE="status"
    else
        SETUP_VIEW_MODE="logs"
    fi
    render_setup_running
}

setup_poll_running_key() {
    local pid="${1:-}" key="" rest=""

    IFS= read -rsn1 -t 0.05 key || return 0

    case "${key}" in
        x|X)
            setup_toggle_running_view
            ;;
        q|Q)
            if [[ -n "${pid}" ]]; then
                kill "${pid}" >/dev/null 2>&1 || true
                wait "${pid}" >/dev/null 2>&1 || true
            fi
            exit 0
            ;;
        $'\033')
            IFS= read -rsn2 -t 0.01 rest || true
            ;;
    esac
}

setup_tick_running() {
    SETUP_SPINNER_FRAME=$(( SETUP_SPINNER_FRAME + 1 ))
    if [[ "${SETUP_VIEW_MODE}" == "status" ]]; then
        render_setup_running_spinner_only
    fi
}

setup_log() {
    SETUP_LOG+=("$*")
    if (( ${#SETUP_LOG[@]} > 200 )); then
        SETUP_LOG=("${SETUP_LOG[@]: -200}")
    fi

    setup_poll_running_key

    if [[ "${SETUP_VIEW_MODE}" == "logs" ]]; then
        render_setup_running_logs_only
    else
        render_setup_running_status_only
    fi
}

run_logged() {
    local label="$1"
    shift

    setup_log "      ${label}"

    "$@" >>"${SETUP_COMMAND_LOG}" 2>&1 &
    local pid=$!

    while kill -0 "${pid}" >/dev/null 2>&1; do
        setup_poll_running_key "${pid}"
        setup_tick_running
        sleep 0.08
    done

    if wait "${pid}"; then
        return 0
    fi

    SETUP_ERR="Command failed: ${label}. See ${SETUP_COMMAND_LOG}"
    setup_log "ERROR: ${SETUP_ERR}"
    return 1
}

download_weights() {
    local model_idx="$1"
    local size_label="$2"
    local model_name="${MODEL_NAMES[$model_idx]}"
    local map_key="${model_idx}|${size_label}"

    setup_set_weight_size_current "${model_idx}" "${size_label}"

    if [[ -z "${WEIGHT_MAP[$map_key]+x}" ]]; then
        setup_log "  WARNING: No HuggingFace repo configured for ${model_name} / ${size_label}; skipping."
        setup_finish_weight_size "${model_idx}" "${size_label}" "skipped"
        return 0
    fi

    local hf_repo dir_label dest
    IFS='|' read -r hf_repo dir_label <<< "${WEIGHT_MAP[$map_key]}"
    dest="${SETUP_PLANTBENCH_DIR}/weights/${model_name}/${dir_label}"
    mkdir -p "${dest}"

    if [[ -n "$(find "${dest}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        setup_log "  ✓ ${model_name} / ${size_label} already present; skipping."
        setup_finish_weight_size "${model_idx}" "${size_label}" "done"
        return 0
    fi

    setup_log "  >>> ${model_name} / ${size_label}"
    setup_log "      repo: ${hf_repo}"
    setup_log "      dest: ${dest}"
    run_logged "hf download ${hf_repo}" hf download "${hf_repo}" --local-dir "${dest}" || return 1
    setup_finish_weight_size "${model_idx}" "${size_label}" "done"
}

perform_setup() {
    local m model_name repo_url repo_dir clone_dest sif_path size_entry
    local -a cloned_urls=() pulled_containers=() sizes=()

    SETUP_LOG=()
    SETUP_ERR=""
    : > "${SETUP_COMMAND_LOG}"

    setup_init_running_progress
    render_setup_running

    setup_log "Running PlantBench setup"
    setup_log "Dependency checks: OK"
    setup_log "  CUDA ${CUDA_VERSION}: OK"
    setup_log "  apptainer: OK"
    setup_log "  git: OK"
    setup_log "  hf: OK"
    setup_log "Save directory: ${SETUP_SAVE_DIR}"
    setup_log "Install root: ${SETUP_PLANTBENCH_DIR}"
    setup_log ""

    mkdir -p "${SETUP_PLANTBENCH_DIR}/repos" "${SETUP_PLANTBENCH_DIR}/containers" "${SETUP_PLANTBENCH_DIR}/weights"
    setup_log "Created directory structure"
    setup_log "  ${SETUP_PLANTBENCH_DIR}/"
    setup_log "  ├── repos/"
    setup_log "  ├── containers/"
    setup_log "  └── weights/"
    setup_log ""

    for m in "${SELECTED_MODELS[@]}"; do
        model_name="${MODEL_NAMES[$m]}"
        setup_set_model_current "${m}"
        setup_log ">>> ${model_name}"

        if [[ "${SETUP_MODE}" == "modify" ]]; then
            setup_set_step_current "${m}" "Downloading model weights"
            local dir_label remove_any=0
            IFS='|' read -ra sizes <<< "${MODEL_SIZES[$m]}"
            for size_entry in "${sizes[@]}"; do
                if model_size_installed "${m}" "${size_entry}" && ! is_size_selected "${m}" "${size_entry}"; then
                    dir_label="$(model_size_dir_label "${m}" "${size_entry}")" || continue
                    remove_any=1
                    run_logged "remove ${model_name} ${dir_label} weights" rm -rf "${SETUP_PLANTBENCH_DIR}/weights/${model_name}/${dir_label}" || return 1
                    setup_log "  ✓ ${model_name} / ${size_entry} removed."
                fi
            done
            if (( remove_any == 0 )); then
                setup_log "  No removals requested for ${model_name}."
            fi
            # Keep weights marked current if this model also has downloads below.
            if ! model_has_selected_payload "${m}"; then
                setup_finish_step "${m}" "Downloading model weights" "done"
                setup_finish_step "${m}" "Pulling container" "skipped"
                setup_finish_step "${m}" "Cloning repo" "skipped"
                setup_finish_model "${m}"
                setup_log ""
                continue
            fi
        elif ! model_has_selected_payload "${m}"; then
            setup_finish_step "${m}" "Pulling container" "skipped"
            setup_finish_step "${m}" "Cloning repo" "skipped"
            setup_finish_step "${m}" "Downloading model weights" "skipped"
            setup_finish_model "${m}"
            setup_log ""
            continue
        fi

        setup_set_step_current "${m}" "Pulling container"
        if [[ " ${pulled_containers[*]} " == *" ${m} "* ]]; then
            setup_log "  [shared] ${model_name} container already handled."
            setup_finish_step "${m}" "Pulling container" "done"
        elif [[ -z "${CONTAINER_MAP[$m]+x}" ]]; then
            setup_log "  [STUB] ${model_name} — container link not configured; skipping."
            pulled_containers+=("${m}")
            setup_finish_step "${m}" "Pulling container" "skipped"
        else
            pulled_containers+=("${m}")
            sif_path="${SETUP_PLANTBENCH_DIR}/containers/${CONTAINER_FILE_MAP[$m]}"
            setup_log "  Container"
            setup_log "      source: ${CONTAINER_MAP[$m]}"
            setup_log "      dest: ${sif_path}"
            run_logged "apptainer pull ${CONTAINER_FILE_MAP[$m]}" apptainer pull "${sif_path}" "${CONTAINER_MAP[$m]}" || return 1
            setup_log "  ✓ ${model_name} container pulled."
            setup_finish_step "${m}" "Pulling container" "done"
        fi

        setup_set_step_current "${m}" "Cloning repo"
        repo_url="${REPO_MAP[$m]}"
        repo_dir="${REPO_DIR_MAP[$repo_url]}"
        clone_dest="${SETUP_PLANTBENCH_DIR}/repos/${repo_dir}"

        if [[ " ${cloned_urls[*]} " == *" ${repo_url} "* ]]; then
            setup_log "  [shared] ${model_name} → repos/${repo_dir}"
            setup_finish_step "${m}" "Cloning repo" "done"
        else
            cloned_urls+=("${repo_url}")
            setup_log "  Repo"
            setup_log "      repo: ${repo_url}"
            setup_log "      dest: ${clone_dest}"

            if [[ -d "${clone_dest}/.git" ]]; then
                run_logged "git pull ${repo_dir}" git -C "${clone_dest}" pull || return 1
            else
                run_logged "git clone ${repo_dir}" git clone --depth 1 "${repo_url}" "${clone_dest}" || return 1
            fi

            setup_log "  ✓ ${model_name} repo ready."
            setup_finish_step "${m}" "Cloning repo" "done"
        fi

        setup_set_step_current "${m}" "Downloading model weights"
        IFS='|' read -ra sizes <<< "${MODEL_SIZES[$m]}"
        for size_entry in "${sizes[@]}"; do
            if contains_single_size_model "${m}" && [[ "${SETUP_MODE}" != "modify" ]]; then
                SETUP_WEIGHT_SIZE_RUN_STATUS["${m}|${size_entry}"]="pending"
            elif is_size_selected "${m}" "${size_entry}"; then
                SETUP_WEIGHT_SIZE_RUN_STATUS["${m}|${size_entry}"]="pending"
            else
                SETUP_WEIGHT_SIZE_RUN_STATUS["${m}|${size_entry}"]=""
            fi
        done
        setup_log "  Weights"
        if contains_single_size_model "${m}" && [[ "${SETUP_MODE}" != "modify" ]]; then
            download_weights "${m}" "${MODEL_SIZES[$m]}" || return 1
        else
            IFS='|' read -ra sizes <<< "${MODEL_SIZES[$m]}"
            for size_entry in "${sizes[@]}"; do
                if is_size_selected "${m}" "${size_entry}"; then
                    download_weights "${m}" "${size_entry}" || return 1
                fi
            done
        fi
        setup_finish_step "${m}" "Downloading model weights" "done"
        setup_finish_model "${m}"
        setup_log ""
    done

    setup_log "All selected models processed."
    setup_log "Weights saved to: ${SETUP_PLANTBENCH_DIR}/weights/"
    PLANTBENCH_DIR="${SETUP_PLANTBENCH_DIR}"
    return 0
}

# ─── Screen renderers ─────────────────────────────────────────────────────────

render_statusbar() {
    move "${LINES}" 3
    printf 'PlantBench'

    local hint="↑ ↓  navigate   ↵  select   q  quit"
    case "${STATE}" in
        setup_save_dir) hint="↵  continue   esc  cancel   q  quit" ;;
        setup_existing_install) hint="↑ ↓  navigate   ↵  select   esc  back   q  quit" ;;
        setup_removing_install) hint="removing   q  quit" ;;
        setup_models|setup_sizes) hint="↑ ↓  navigate   space  toggle   a  all   ↵  continue   esc  back   q  quit" ;;
        setup_confirm) hint="y/↵  install   n/esc  cancel   q  quit" ;;
        setup_running) hint="x  toggle logs   q  quit" ;;
        setup_done|setup_error) hint="any key  return   q  quit" ;;
        main_stub) hint="any key  return   q  quit" ;;
        manual_input) hint="↵  apply   esc  cancel   q  quit" ;;
    esac

    move "${LINES}" $(( COLS - ${#hint} - 2 ))
    printf '%s' "${hint}"
}

render_no_install_menu_only() {
    COLS=$(tput cols)
    LINES=$(tput lines)

    (( COLS < MIN_COLS || LINES < MIN_LINES )) && return

    local title_h=5
    local info_box_w=75
    wrap_text_for_box "${INFO_TEXT}" $(( info_box_w - 4 ))
    local info_box_h=$(( ${#WRAPPED_LINES[@]} + 4 ))
    local sub_box_h=5
    local total_h=$(( title_h + 2 + info_box_h + 2 + sub_box_h + 2 + ${#NO_INSTALL_MENU[@]} ))
    local row=$(( (LINES - total_h) / 2 ))
    (( row < 2 )) && row=2

    # Keep this in sync with render_no_install's vertical layout:
    # title, 2 blank lines, paper-info box, 2 blank lines, no-install box, 2 blank lines.
    row=$(( row + title_h + 2 + info_box_h + 2 + sub_box_h + 2 ))

    local max_w=0 i
    for i in "${!NO_INSTALL_MENU[@]}"; do
        (( ${#NO_INSTALL_MENU[$i]} > max_w )) && max_w=${#NO_INSTALL_MENU[$i]}
    done

    local menu_col=$(( (COLS - max_w - 4) / 2 ))
    local clear_w=$(( max_w + 4 ))

    for i in "${!NO_INSTALL_MENU[@]}"; do
        move "${row}" "${menu_col}"
        printf '%*s' "${clear_w}" ''

        move "${row}" "${menu_col}"
        if (( i == MENU_IDX )); then
            printf '▶  %s' "${NO_INSTALL_MENU[$i]}"
        else
            printf '   %s' "${NO_INSTALL_MENU[$i]}"
        fi
        (( row++ ))
    done
}

render_no_install() {
    # ── PLANT (figlet standard, all rows same width) ──────────────────────────
    # Each row is exactly 37 chars. Verified char-by-char.
    local -a PLANT=(
        ' ____   _         _     _   _  _____ '
        '|  _ \ | |       / \   | \ | ||_   _|'
        '| |_) || |      / _ \  |  \| |  | |  '
        '|  __/ | |___  / ___ \ | |\  |  | |  '
        '|_|    |_____|/_/   \_\|_| \_|  |_|  '
    )

    # ── BENCH (figlet standard, all rows exactly 35 chars) ───────────────────
    # Each letter is 7 chars wide: B(7)+E(7)+N(7)+C(7)+H(7) = 35
    local -a BENCH=(
        ' ____   _____  _   _   ____  _   _ '
        '| __ ) | ____|| \ | | / ___|| | | |'
        '|  _ \ |  _|  |  \| || |    | |_| |'
        '| |_) || |___ | |\  || |___ |  _  |'
        '|____/ |_____||_| \_| \____||_| |_|'
    )

    local plant_w=${#PLANT[1]}
    local bench_w=${#BENCH[1]}
    local title_w=$(( plant_w + 3 + bench_w ))

    local title_col=$(( (COLS - title_w) / 2 ))

    local info_box_w=${title_w}
    wrap_text_for_box "${INFO_TEXT}" $(( info_box_w - 4 ))
    local info_box_h=$(( ${#WRAPPED_LINES[@]} + 4 ))

    local sub='No installation found'
    local sub_box_w=$(( ${#sub} + 12 ))
    local sub_box_h=5

    local total_h=$(( ${#PLANT[@]} + 2 + info_box_h + 2 + sub_box_h + 2 + ${#NO_INSTALL_MENU[@]} ))
    local row=$(( (LINES - total_h) / 2 ))
    (( row < 2 )) && row=2

    local i

    for i in "${!PLANT[@]}"; do
        move "${row}" "${title_col}"
        printf '%-*s   %s' "${plant_w}" "${PLANT[$i]}" "${BENCH[$i]}"
        (( row++ ))
    done
    (( row += 2 ))

    local info_box_col=$(( (COLS - info_box_w) / 2 ))
    draw_round_box "${row}" "${info_box_col}" "${info_box_h}" "${info_box_w}"
    move $(( row + 1 )) $(( info_box_col + 2 ))
    printf '%s' "${INFO_LINE1}"
    draw_hline $(( row + 2 )) "${info_box_col}" "${info_box_w}"
    for i in "${!WRAPPED_LINES[@]}"; do
        move $(( row + 3 + i )) $(( info_box_col + 2 ))
        printf '%s' "${WRAPPED_LINES[$i]}"
    done
    (( row += info_box_h + 2 ))

    local sub_box_col=$(( (COLS - sub_box_w) / 2 ))
    draw_round_box "${row}" "${sub_box_col}" "${sub_box_h}" "${sub_box_w}"
    move $(( row + sub_box_h / 2 )) $(( sub_box_col + (sub_box_w - ${#sub}) / 2 ))
    printf '%s' "${sub}"
    (( row += sub_box_h + 2 ))

    local max_w=0
    for i in "${!NO_INSTALL_MENU[@]}"; do
        (( ${#NO_INSTALL_MENU[$i]} > max_w )) && max_w=${#NO_INSTALL_MENU[$i]}
    done
    local menu_col=$(( (COLS - max_w - 4) / 2 ))

    for i in "${!NO_INSTALL_MENU[@]}"; do
        move "${row}" "${menu_col}"
        if (( i == MENU_IDX )); then
            printf '▶  %s' "${NO_INSTALL_MENU[$i]}"
        else
            printf '   %s' "${NO_INSTALL_MENU[$i]}"
        fi
        (( row++ ))
    done
}

render_installed_menu_only() {
    COLS=$(tput cols)
    LINES=$(tput lines)

    (( COLS < MIN_COLS || LINES < MIN_LINES )) && return

    local model_box_w=$(( COLS - 8 ))
    (( model_box_w > 126 )) && model_box_w=126
    (( model_box_w > COLS - 4 )) && model_box_w=$(( COLS - 4 ))

    local install_box_h=3
    local model_box_h=11
    local menu_h=${#MAIN_MENU[@]}
    local install_top=$(( LINES - install_box_h - 2 ))

    # Recompute the model-availability box top exactly as render_install_found does.
    local -a PLANT=(
        ' ____   _         _     _   _  _____ '
        '|  _ \ | |       / \   | \ | ||_   _|'
        '| |_) || |      / _ \  |  \| |  | |  '
        '|  __/ | |___  / ___ \ | |\  |  | |  '
        '|_|    |_____|/_/   \_\|_| \_|  |_|  '
    )
    local -a BENCH=(
        ' ____   _____  _   _   ____  _   _ '
        '| __ ) | ____|| \ | | / ___|| | | |'
        '|  _ \ |  _|  |  \| || |    | |_| |'
        '| |_) || |___ | |\  || |___ |  _  |'
        '|____/ |_____||_| \_| \____||_| |_|'
    )
    local plant_w=${#PLANT[1]}
    local bench_w=${#BENCH[1]}
    local title_w=$(( plant_w + 3 + bench_w ))
    (( model_box_w < title_w )) && model_box_w=${title_w}

    local info_box_w=${title_w}
    wrap_text_for_box "${INFO_TEXT}" $(( info_box_w - 4 ))
    local info_box_h=$(( ${#WRAPPED_LINES[@]} + 4 ))
    local total_h=$(( ${#PLANT[@]} + 2 + info_box_h + 2 + model_box_h ))
    local row=$(( (LINES - total_h) / 2 - 2 ))
    (( row < 2 )) && row=2
    row=$(( row + ${#PLANT[@]} + 2 + info_box_h + 2 ))

    (( install_top < row + model_box_h + menu_h + 4 )) && install_top=$(( row + model_box_h + menu_h + 4 ))

    # Keep two blank lines between the model availability box and the installed-home menu.
    local menu_start=$(( row + model_box_h + 2 ))

    local max_w=0 i
    for i in "${!MAIN_MENU[@]}"; do
        (( ${#MAIN_MENU[$i]} > max_w )) && max_w=${#MAIN_MENU[$i]}
    done

    local menu_col=$(( (COLS - max_w - 4) / 2 ))
    local clear_w=$(( max_w + 4 ))
    local r=${menu_start}
    for i in "${!MAIN_MENU[@]}"; do
        move "${r}" "${menu_col}"
        printf '%*s' "${clear_w}" ''
        move "${r}" "${menu_col}"
        if (( i == MAIN_MENU_IDX )); then
            printf '▶  %s' "${MAIN_MENU[$i]}"
        else
            printf '   %s' "${MAIN_MENU[$i]}"
        fi
        (( r++ ))
    done
}

render_install_found() {
    # Installed-home screen:
    # keep the PlantBench logo + paper callout from the no-install screen,
    # then show every supported model in a horizontal status grid.
    local -a PLANT=(
        ' ____   _         _     _   _  _____ '
        '|  _ \ | |       / \   | \ | ||_   _|'
        '| |_) || |      / _ \  |  \| |  | |  '
        '|  __/ | |___  / ___ \ | |\  |  | |  '
        '|_|    |_____|/_/   \_\|_| \_|  |_|  '
    )

    local -a BENCH=(
        ' ____   _____  _   _   ____  _   _ '
        '| __ ) | ____|| \ | | / ___|| | | |'
        '|  _ \ |  _|  |  \| || |    | |_| |'
        '| |_) || |___ | |\  || |___ |  _  |'
        '|____/ |_____||_| \_| \____||_| |_|'
    )

    local plant_w=${#PLANT[1]}
    local bench_w=${#BENCH[1]}
    local title_w=$(( plant_w + 3 + bench_w ))
    local title_col=$(( (COLS - title_w) / 2 ))

    local info_box_w=${title_w}
    wrap_text_for_box "${INFO_TEXT}" $(( info_box_w - 4 ))
    local info_box_h=$(( ${#WRAPPED_LINES[@]} + 4 ))

    local model_box_w=$(( COLS - 8 ))
    (( model_box_w > 126 )) && model_box_w=126
    (( model_box_w < title_w )) && model_box_w=${title_w}
    (( model_box_w > COLS - 4 )) && model_box_w=$(( COLS - 4 ))

    local install_box_h=3
    local model_box_h=11
    # Main content flow: logo, paper-info box, then model availability.
    # The installation path is drawn separately near the bottom center.
    local total_h=$(( ${#PLANT[@]} + 2 + info_box_h + 2 + model_box_h ))
    local row=$(( (LINES - total_h) / 2 - 2 ))
    (( row < 2 )) && row=2

    local i
    for i in "${!PLANT[@]}"; do
        move "${row}" "${title_col}"
        printf '%-*s   %s' "${plant_w}" "${PLANT[$i]}" "${BENCH[$i]}"
        (( row++ ))
    done
    (( row += 2 ))

    local info_box_col=$(( (COLS - info_box_w) / 2 ))
    draw_round_box "${row}" "${info_box_col}" "${info_box_h}" "${info_box_w}"
    move $(( row + 1 )) $(( info_box_col + 2 ))
    printf '%s' "${INFO_LINE1}"
    draw_hline $(( row + 2 )) "${info_box_col}" "${info_box_w}"
    for i in "${!WRAPPED_LINES[@]}"; do
        move $(( row + 3 + i )) $(( info_box_col + 2 ))
        printf '%s' "${WRAPPED_LINES[$i]}"
    done
    # Two blank lines between the paper-info box and model availability.
    (( row += info_box_h + 2 ))

    local box_col=$(( (COLS - model_box_w) / 2 ))

    draw_round_box "${row}" "${box_col}" "${model_box_h}" "${model_box_w}"

    local header='Model availability'
    move $(( row + 1 )) $(( box_col + 2 ))
    printf '%s' "${header}"

    draw_hline $(( row + 2 )) "${box_col}" "${model_box_w}"

    local content_w=$(( model_box_w - 6 ))
    local gap=2
    local col_w=$(( (content_w - gap * 5) / 6 ))
    if (( col_w < 11 )); then
        gap=1
        col_w=$(( (content_w - gap * 5) / 6 ))
    fi

    local m col name_row size_row size_idx size_entry map_key dir_label status label line
    name_row=$(( row + 4 ))

    for (( m = 1; m <= 6; m++ )); do
        col=$(( box_col + 3 + (m - 1) * (col_w + gap) ))
        move "${name_row}" "${col}"
        print_clipped "${col_w}" "${MODEL_NAMES[$m]}"
    done

    for (( size_idx = 0; size_idx < 3; size_idx++ )); do
        size_row=$(( row + 5 + size_idx ))
        for (( m = 1; m <= 6; m++ )); do
            local -a size_options=()
            IFS='|' read -ra size_options <<< "${MODEL_SIZES[$m]}"

            col=$(( box_col + 3 + (m - 1) * (col_w + gap) ))
            move "${size_row}" "${col}"

            if (( size_idx < ${#size_options[@]} )); then
                size_entry="${size_options[$size_idx]}"
                map_key="${m}|${size_entry}"
                status='[ ]'

                if [[ -n "${WEIGHT_MAP[$map_key]+x}" ]]; then
                    IFS='|' read -r _ dir_label <<< "${WEIGHT_MAP[$map_key]}"
                    if [[ -d "${PLANTBENCH_DIR}/weights/${MODEL_NAMES[$m]}/${dir_label}" ]]; then
                        status='[x]'
                    fi
                fi

                label="$(size_short_label "${size_entry}")"
                line="${status} ${label}"
                print_clipped "${col_w}" "${line}"
            fi
        done
    done

    draw_hline $(( row + model_box_h - 3 )) "${box_col}" "${model_box_w}"
    move $(( row + model_box_h - 2 )) $(( box_col + 3 ))
    printf '[x] installed   [ ] not found'

    # Installation directory sits independently at the bottom center,
    # just above the outer/status border area.
    local install_label="Installation: ${PLANTBENCH_DIR}"
    local install_box_w=$(( ${#install_label} + 4 ))
    (( install_box_w > model_box_w )) && install_box_w=${model_box_w}
    local install_box_col=$(( (COLS - install_box_w) / 2 ))
    local install_top=$(( LINES - install_box_h - 2 ))

    local menu_h=${#MAIN_MENU[@]}
    (( install_top < row + model_box_h + menu_h + 4 )) && install_top=$(( row + model_box_h + menu_h + 4 ))

    # Keep two blank lines between the model availability box and the installed-home menu.
    local menu_start=$(( row + model_box_h + 2 ))

    local menu_max_w=0
    for i in "${!MAIN_MENU[@]}"; do
        (( ${#MAIN_MENU[$i]} > menu_max_w )) && menu_max_w=${#MAIN_MENU[$i]}
    done
    local menu_col=$(( (COLS - menu_max_w - 4) / 2 ))

    for i in "${!MAIN_MENU[@]}"; do
        move $(( menu_start + i )) "${menu_col}"
        if (( i == MAIN_MENU_IDX )); then
            printf '▶  %s' "${MAIN_MENU[$i]}"
        else
            printf '   %s' "${MAIN_MENU[$i]}"
        fi
    done

    # Hide the bottom installation box while the manual path-entry overlay is active;
    # otherwise the two bottom panels overlap visually.
    if [[ "${STATE}" != "manual_input" ]]; then
        draw_round_box "${install_top}" "${install_box_col}" "${install_box_h}" "${install_box_w}"
        move $(( install_top + 1 )) $(( install_box_col + 2 ))
        print_clipped $(( install_box_w - 4 )) "${install_label}"
    fi
}

render_main_stub() {
    local W=64 H=7
    local T=$(( (LINES - H) / 2 )) L=$(( (COLS - W) / 2 ))
    draw_round_box "${T}" "${L}" "${H}" "${W}"

    local row=$(( T + 2 ))
    move "${row}" $(( L + 3 ))
    print_clipped $(( W - 6 )) "${MAIN_STUB_TITLE:-Not implemented}"
    draw_hline $(( T + 3 )) "${L}" "${W}"
    row=$(( T + 5 ))
    move "${row}" $(( L + 3 ))
    printf 'This option is not implemented yet.'
}

render_manual_input() {
    local W=$(( COLS - 8 )) row=$(( LINES - 6 ))
    local L=5
    draw_box "${row}" "${L}" 5 "${W}"

    local label="Enter path to plantbench directory  (esc to cancel)"
    move $(( row + 1 )) $(( L + 3 ))
    printf '%s' "${label}"

    move $(( row + 2 )) $(( L + 3 ))
    printf '> %s' "${MANUAL_INPUT}"

    if [[ -n "${MANUAL_ERR}" ]]; then
        move $(( row + 3 )) $(( L + 3 ))
        printf '  %s' "${MANUAL_ERR}"
    fi

    move $(( row + 2 )) $(( L + 5 + ${#MANUAL_INPUT} ))
    show_cursor
}

render_manual_input_only() {
    COLS=$(tput cols)
    LINES=$(tput lines)

    (( COLS < MIN_COLS || LINES < MIN_LINES )) && return

    local W=$(( COLS - 8 )) row=$(( LINES - 6 ))
    local L=5
    local content_w=$(( W - 6 ))
    local input_row=$(( row + 2 ))
    local err_row=$(( row + 3 ))
    local cursor_col

    move "${input_row}" $(( L + 3 ))
    printf '%*s' "${content_w}" ''
    move "${input_row}" $(( L + 3 ))
    print_clipped "${content_w}" "> ${MANUAL_INPUT}"

    move "${err_row}" $(( L + 3 ))
    printf '%*s' "${content_w}" ''
    if [[ -n "${MANUAL_ERR}" ]]; then
        move "${err_row}" $(( L + 3 ))
        print_clipped "${content_w}" "  ${MANUAL_ERR}"
    fi

    cursor_col=$(( L + 5 + ${#MANUAL_INPUT} ))
    (( cursor_col > L + 2 + content_w )) && cursor_col=$(( L + 2 + content_w ))
    move "${input_row}" "${cursor_col}"
    show_cursor
}

render_setup_save_dir() {
    local W; W="$(setup_box_width 100)"
    local content_w=$(( W - 6 ))
    local prompt="Enter a custom path, 'share' for ~/hpc-share, or leave blank to save into project root"
    local default_text="Root: ${SCRIPT_DIR}"

    wrap_text_for_box "${prompt}" "${content_w}"
    local prompt_lines=("${WRAPPED_LINES[@]}")
    wrap_text_for_box "${default_text}" "${content_w}"
    local default_lines=("${WRAPPED_LINES[@]}")

    local H=$(( 11 + ${#prompt_lines[@]} + ${#default_lines[@]} ))
    local T=$(( (LINES - H) / 2 )) L=$(( (COLS - W) / 2 ))
    draw_round_box "${T}" "${L}" "${H}" "${W}"

    local row=$(( T + 2 )) i input_row cursor_col
    move "${row}" $(( L + 3 )); printf 'Setup'
    move "${row}" $(( L + W - 18 )); printf 'Dependencies OK'
    draw_hline $(( T + 3 )) "${L}" "${W}"

    row=$(( T + 5 ))
    move "${row}" $(( L + 3 )); printf 'Save directory'
    (( row += 2 ))

    for i in "${!prompt_lines[@]}"; do
        move "${row}" $(( L + 3 ))
        print_clipped "${content_w}" "${prompt_lines[$i]}"
        (( row++ ))
    done

    (( row++ ))
    input_row="${row}"
    move "${input_row}" $(( L + 3 ))
    print_clipped "${content_w}" "> ${SETUP_SAVE_INPUT}"

    (( row += 2 ))
    for i in "${!default_lines[@]}"; do
        move "${row}" $(( L + 3 ))
        print_clipped "${content_w}" "${default_lines[$i]}"
        (( row++ ))
    done

    cursor_col=$(( L + 5 + ${#SETUP_SAVE_INPUT} ))
    (( cursor_col > L + 2 + content_w )) && cursor_col=$(( L + 2 + content_w ))
    move "${input_row}" "${cursor_col}"
    show_cursor
}

render_setup_save_dir_input_only() {
    COLS=$(tput cols)
    LINES=$(tput lines)

    (( COLS < MIN_COLS || LINES < MIN_LINES )) && return

    local W; W="$(setup_box_width 100)"
    local content_w=$(( W - 6 ))
    local prompt="Enter a custom path, 'share' for ~/hpc-share, or leave blank to save into project root"
    local default_text="Root: ${SCRIPT_DIR}"

    wrap_text_for_box "${prompt}" "${content_w}"
    local prompt_lines=("${WRAPPED_LINES[@]}")
    wrap_text_for_box "${default_text}" "${content_w}"
    local default_lines=("${WRAPPED_LINES[@]}")

    local H=$(( 11 + ${#prompt_lines[@]} + ${#default_lines[@]} ))
    local T=$(( (LINES - H) / 2 )) L=$(( (COLS - W) / 2 ))
    local row=$(( T + 5 + 2 + ${#prompt_lines[@]} + 1 ))
    local cursor_col

    move "${row}" $(( L + 3 ))
    printf '%*s' "${content_w}" ''
    move "${row}" $(( L + 3 ))
    print_clipped "${content_w}" "> ${SETUP_SAVE_INPUT}"

    cursor_col=$(( L + 5 + ${#SETUP_SAVE_INPUT} ))
    (( cursor_col > L + 2 + content_w )) && cursor_col=$(( L + 2 + content_w ))
    move "${row}" "${cursor_col}"
    show_cursor
}


render_setup_installation_box() {
    [[ -z "${SETUP_PLANTBENCH_DIR}" ]] && return

    COLS=$(tput cols)
    LINES=$(tput lines)
    (( COLS < MIN_COLS || LINES < MIN_LINES )) && return

    local max_w=$(( COLS - 8 ))
    (( max_w > 126 )) && max_w=126
    (( max_w < 50 )) && max_w=50

    local prefix="Installation"
    [[ "${SETUP_PATH_LABEL_MODE}" == "selected" ]] && prefix="Selected path"
    local label="${prefix}: ${SETUP_PLANTBENCH_DIR}"
    local box_w=$(( ${#label} + 4 ))
    (( box_w > max_w )) && box_w=${max_w}

    local box_h=3
    local top=$(( LINES - box_h - 2 ))
    local left=$(( (COLS - box_w) / 2 ))

    draw_round_box "${top}" "${left}" "${box_h}" "${box_w}"
    move $(( top + 1 )) $(( left + 2 ))
    print_clipped $(( box_w - 4 )) "${label}"
}

model_install_status_text() {
    local m="$1"
    local -a size_options installed=() missing=()
    local size_entry map_key dir_label

    IFS='|' read -ra size_options <<< "${MODEL_SIZES[$m]}"

    for size_entry in "${size_options[@]}"; do
        map_key="${m}|${size_entry}"

        if [[ -n "${WEIGHT_MAP[$map_key]+x}" ]]; then
            IFS='|' read -r _ dir_label <<< "${WEIGHT_MAP[$map_key]}"
            if [[ -d "${SETUP_PLANTBENCH_DIR}/weights/${MODEL_NAMES[$m]}/${dir_label}" ]]; then
                installed+=("${size_entry}")
            else
                missing+=("${size_entry}")
            fi
        else
            missing+=("${size_entry}")
        fi
    done

    if (( ${#installed[@]} == 0 )); then
        printf 'Not installed'
    elif (( ${#missing[@]} == 0 )); then
        printf 'Already installed'
    else
        printf 'Partially installed; some sizes missing'
    fi
}

model_size_availability_line() {
    local m="$1"
    local -a size_options=()
    local size_entry map_key dir_label status label token line=""

    IFS='|' read -ra size_options <<< "${MODEL_SIZES[$m]}"

    for size_entry in "${size_options[@]}"; do
        map_key="${m}|${size_entry}"
        status='[ ]'

        if [[ -n "${WEIGHT_MAP[$map_key]+x}" ]]; then
            IFS='|' read -r _ dir_label <<< "${WEIGHT_MAP[$map_key]}"
            if [[ -d "${SETUP_PLANTBENCH_DIR}/weights/${MODEL_NAMES[$m]}/${dir_label}" ]]; then
                status='[x]'
            fi
        fi

        label="$(size_short_label "${size_entry}")"
        token="${status} ${label}"
        [[ -z "${line}" ]] && line="${token}" || line+="   ${token}"
    done

    printf '%s' "${line}"
}

render_setup_model_status_box() {
    [[ "${SETUP_MODE}" != "modify" ]] && return
    [[ -z "${SETUP_PLANTBENCH_DIR}" ]] && return

    local top="$1" left="$2" width="$3"
    local m=$(( SETUP_MENU_IDX + 1 ))
    local status_text="$(model_install_status_text "${m}")"
    local H=5
    local box_w=$(( ${#status_text} + 12 ))
    (( box_w > width )) && box_w=${width}
    local box_left=$(( left + (width - box_w) / 2 ))

    # Clear a stable region so shorter status / size boxes do not leave stale chars.
    local r clear_h=10
    for (( r = 0; r < clear_h; r++ )); do
        move $(( top + r )) "${left}"
        printf '%*s' "${width}" ''
    done

    (( top + H > LINES - 5 )) && return

    draw_round_box "${top}" "${box_left}" "${H}" "${box_w}"
    move $(( top + H / 2 )) $(( box_left + (box_w - ${#status_text}) / 2 ))
    printf '%s' "${status_text}"

    local size_line="$(model_size_availability_line "${m}")"
    local size_H=3
    local size_w=$(( ${#size_line} + 6 ))
    (( size_w > width )) && size_w=${width}
    local size_left=$(( left + (width - size_w) / 2 ))
    local size_top=$(( top + H ))

    (( size_top + size_H > LINES - 5 )) && return

    draw_round_box "${size_top}" "${size_left}" "${size_H}" "${size_w}"
    move $(( size_top + 1 )) $(( size_left + (size_w - ${#size_line}) / 2 ))
    print_clipped $(( size_w - 4 )) "${size_line}"
}

setup_models_selector_top() {
    local W; W="$(setup_box_width 100)"
    local selector_h=15
    local content_w=$(( W - 6 ))
    local m=$(( SETUP_MENU_IDX + 1 ))

    wrap_text_for_box "${MODEL_INFO_BODY[$m]}" "${content_w}"
    local info_h=$(( ${#WRAPPED_LINES[@]} + 5 ))

    # Center only the model selector + model-info box as a single visual group.
    # The modify-status and size-availability boxes are intentionally not part
    # of this centering calculation; they remain directly below the info box.
    local install_top=$(( LINES - 5 ))
    local content_h=$(( selector_h + info_h ))
    local center_t=$(( (LINES - content_h) / 2 ))
    local max_t=$(( install_top - content_h - 1 ))

    local top=${center_t}
    (( top > max_t )) && top=${max_t}
    (( top < 2 )) && top=2
    printf '%d' "${top}"
}

render_setup_model_info_box() {
    COLS=$(tput cols)
    LINES=$(tput lines)

    (( COLS < MIN_COLS || LINES < MIN_LINES )) && return

    local W; W="$(setup_box_width 100)"
    local selector_h=15
    local selector_t; selector_t="$(setup_models_selector_top)"
    local L=$(( (COLS - W) / 2 ))
    local T=$(( selector_t + selector_h ))
    local m=$(( SETUP_MENU_IDX + 1 ))
    local content_w=$(( W - 6 ))

    wrap_text_for_box "${MODEL_INFO_BODY[$m]}" "${content_w}"
    local H=$(( ${#WRAPPED_LINES[@]} + 5 ))

    # Avoid drawing into the bottom installation box on very short terminals.
    local install_top=$(( LINES - 5 ))
    (( T + H >= install_top )) && return

    # Clear the whole model-info region before redrawing it. Without this,
    # shorter model titles leave stale characters from the previously highlighted
    # model, making dates appear corrupted.
    local clear_h=18 r
    (( T + clear_h >= LINES )) && clear_h=$(( LINES - T - 1 ))
    for (( r = 0; r < clear_h; r++ )); do
        move $(( T + r )) "${L}"
        printf '%*s' "${W}" ''
    done

    draw_round_box "${T}" "${L}" "${H}" "${W}"
    move $(( T + 1 )) $(( L + 3 ))
    printf '%*s' "${content_w}" ''

    local model_title="${MODEL_INFO_TITLE[$m]}"
    local model_date="${MODEL_INFO_DATE[$m]}"
    local date_col=$(( L + 3 + content_w - ${#model_date} ))
    local title_w=$(( content_w - ${#model_date} - 3 ))
    (( title_w < 0 )) && title_w=0

    move $(( T + 1 )) $(( L + 3 ))
    print_clipped "${title_w}" "${model_title}"
    move $(( T + 1 )) "${date_col}"
    printf '%s' "${model_date}"
    draw_hline $(( T + 2 )) "${L}" "${W}"

    local i row=$(( T + 4 ))
    for i in "${!WRAPPED_LINES[@]}"; do
        move "${row}" $(( L + 3 ))
        printf '%*s' "${content_w}" ''
        move "${row}" $(( L + 3 ))
        print_clipped "${content_w}" "${WRAPPED_LINES[$i]}"
        (( row++ ))
    done

    if [[ "${SETUP_MODE}" == "modify" ]]; then
        render_setup_model_status_box $(( T + H + 1 )) "${L}" "${W}"
    fi
}

render_setup_existing_install() {
    local W; W="$(setup_box_width 100)"
    local H=16
    local T=$(( (LINES - H) / 2 ))
    local L=$(( (COLS - W) / 2 ))

    draw_round_box "${T}" "${L}" "${H}" "${W}"

    local row=$(( T + 2 ))
    move "${row}" $(( L + 3 ))
    printf 'Existing installation detected'

    draw_hline $(( T + 3 )) "${L}" "${W}"

    row=$(( T + 5 ))
    move "${row}" $(( L + 3 ))
    print_clipped $(( W - 6 )) "An installation already exists at the selected path"

    row=$(( T + 7 ))
    draw_round_box "${row}" $(( L + 3 )) 3 $(( W - 6 ))
    move $(( row + 1 )) $(( L + 5 ))
    print_clipped $(( W - 10 )) "${SETUP_PLANTBENCH_DIR}"

    row=$(( T + 11 ))
    local -a options=(
        "Use existing installation"
        "Remove existing installation and reinstall"
        "Change path"
    )
    local i max_w=0 menu_col
    for i in "${!options[@]}"; do
        (( ${#options[$i]} > max_w )) && max_w=${#options[$i]}
    done
    menu_col=$(( L + (W - max_w - 4) / 2 ))

    for i in "${!options[@]}"; do
        move "${row}" "${menu_col}"
        if (( i == SETUP_EXISTING_MENU_IDX )); then
            printf '▶  %s' "${options[$i]}"
        else
            printf '   %s' "${options[$i]}"
        fi
        (( row++ ))
    done
    (( row++ ))

    if [[ -n "${SETUP_ERR}" ]]; then
        move $(( T + H - 2 )) $(( L + 3 ))
        print_clipped $(( W - 6 )) "${SETUP_ERR}"
    fi
}

render_setup_existing_install_menu_only() {
    COLS=$(tput cols)
    LINES=$(tput lines)
    (( COLS < MIN_COLS || LINES < MIN_LINES )) && return

    local W; W="$(setup_box_width 100)"
    local H=16
    local T=$(( (LINES - H) / 2 ))
    local L=$(( (COLS - W) / 2 ))
    local row=$(( T + 11 ))

    local -a options=(
        "Use existing installation"
        "Remove existing installation and reinstall"
        "Change path"
    )

    local i max_w=0 menu_col clear_w
    for i in "${!options[@]}"; do
        (( ${#options[$i]} > max_w )) && max_w=${#options[$i]}
    done

    menu_col=$(( L + (W - max_w - 4) / 2 ))
    clear_w=$(( max_w + 4 ))

    for i in "${!options[@]}"; do
        move "${row}" "${menu_col}"
        printf '%*s' "${clear_w}" ''

        move "${row}" "${menu_col}"
        if (( i == SETUP_EXISTING_MENU_IDX )); then
            printf '▶  %s' "${options[$i]}"
        else
            printf '   %s' "${options[$i]}"
        fi
        (( row++ ))
    done

    hide_cursor
}


render_setup_removing_install() {
    local W; W="$(setup_box_width 100)"
    local H=14
    local T=$(( (LINES - H) / 2 ))
    local L=$(( (COLS - W) / 2 ))

    draw_round_box "${T}" "${L}" "${H}" "${W}"

    local row=$(( T + 2 ))
    move "${row}" $(( L + 3 ))
    printf 'Removing existing installation'
    move "${row}" $(( L + W - 14 ))
    printf 'please wait'

    draw_hline $(( T + 3 )) "${L}" "${W}"

    row=$(( T + 5 ))
    move "${row}" $(( L + 3 ))
    print_clipped $(( W - 6 )) "Removing the existing PlantBench directory"

    row=$(( T + 7 ))
    draw_round_box "${row}" $(( L + 3 )) 3 $(( W - 6 ))
    move $(( row + 1 )) $(( L + 5 ))
    print_clipped $(( W - 10 )) "${SETUP_PLANTBENCH_DIR}"

    row=$(( T + 11 ))
    local spinner="$(setup_spinner_char)"
    local msg="${spinner}  Removing"
    move "${row}" $(( L + (W - ${#msg}) / 2 ))
    printf '%s' "${msg}"

    hide_cursor
}

render_setup_removing_install_spinner_only() {
    [[ "${STATE}" == "setup_removing_install" ]] || return

    COLS=$(tput cols)
    LINES=$(tput lines)
    (( COLS < MIN_COLS || LINES < MIN_LINES )) && return

    local W; W="$(setup_box_width 100)"
    local H=14
    local T=$(( (LINES - H) / 2 ))
    local L=$(( (COLS - W) / 2 ))
    local row=$(( T + 11 ))
    local clear_w=$(( W - 6 ))

    move "${row}" $(( L + 3 ))
    printf '%*s' "${clear_w}" ''
    move $(( row + 1 )) $(( L + 3 ))
    printf '%*s' "${clear_w}" ''

    local spinner="$(setup_spinner_char)"
    local msg="${spinner}  Removing"
    move "${row}" $(( L + (W - ${#msg}) / 2 ))
    printf '%s' "${msg}"

    hide_cursor
}

perform_existing_install_removal() {
    STATE="setup_removing_install"
    SETUP_SPINNER_FRAME=0
    render

    rm -rf -- "${SETUP_PLANTBENCH_DIR}" >/dev/null 2>&1 &
    local pid=$!
    local key="" rest=""

    while kill -0 "${pid}" >/dev/null 2>&1; do
        IFS= read -rsn1 -t 0.08 key || key=""
        case "${key}" in
            q|Q)
                kill "${pid}" >/dev/null 2>&1 || true
                wait "${pid}" >/dev/null 2>&1 || true
                exit 0
                ;;
            $'\033')
                IFS= read -rsn2 -t 0.01 rest || true
                ;;
        esac

        SETUP_SPINNER_FRAME=$(( SETUP_SPINNER_FRAME + 1 ))
        render_setup_removing_install_spinner_only
    done

    wait "${pid}"
}


render_setup_models() {
    local W; W="$(setup_box_width 100)"
    local H=15
    local T; T="$(setup_models_selector_top)"
    local L=$(( (COLS - W) / 2 ))
    draw_round_box "${T}" "${L}" "${H}" "${W}"

    local row=$(( T + 2 )) i marker checked size_summary line
    move "${row}" $(( L + 3 ))
    if [[ "${SETUP_MODE}" == "modify" ]]; then
        printf 'Select models to modify'
    else
        printf 'Select models to install'
    fi
    draw_hline $(( T + 3 )) "${L}" "${W}"

    row=$(( T + 5 ))
    for (( i = 1; i <= 6; i++ )); do
        checked='[ ]'
        [[ "${SETUP_MODEL_SELECTED[$i]:-0}" == "1" ]] && checked='[x]'
        marker='  '
        (( SETUP_MENU_IDX == i - 1 )) && marker='▶ '
        size_summary="${MODEL_SIZES[$i]//|/, }"

        printf -v line '%s%s  %d. %-11s  sizes: %s'             "${marker}" "${checked}" "${i}" "${MODEL_NAMES[$i]}" "${size_summary}"
        move "${row}" $(( L + 4 ))
        print_clipped $(( W - 8 )) "${line}"
        (( row++ ))
    done

    row=$(( T + H - 4 ))
    if [[ -n "${SETUP_ERR}" ]]; then
        move "${row}" $(( L + 3 )); print_clipped $(( W - 6 )) "${SETUP_ERR}"
    fi
    move $(( T + H - 2 )) $(( L + 3 ))
    print_clipped $(( W - 6 )) 'space toggles, a toggles all, ↵ continues'

    render_setup_model_info_box
    render_setup_installation_box
}

render_setup_models_list_only() {
    COLS=$(tput cols)
    LINES=$(tput lines)

    (( COLS < MIN_COLS || LINES < MIN_LINES )) && return

    local W; W="$(setup_box_width 100)"
    local H=15
    local T; T="$(setup_models_selector_top)"
    local L=$(( (COLS - W) / 2 ))
    local row=$(( T + 5 )) i marker checked size_summary line clear_w
    clear_w=$(( W - 8 ))

    for (( i = 1; i <= 6; i++ )); do
        checked='[ ]'
        [[ "${SETUP_MODEL_SELECTED[$i]:-0}" == "1" ]] && checked='[x]'
        marker='  '
        (( SETUP_MENU_IDX == i - 1 )) && marker='▶ '
        size_summary="${MODEL_SIZES[$i]//|/, }"

        printf -v line '%s%s  %d. %-11s  sizes: %s' "${marker}" "${checked}" "${i}" "${MODEL_NAMES[$i]}" "${size_summary}"
        move "${row}" $(( L + 4 ))
        printf '%*s' "${clear_w}" ''
        move "${row}" $(( L + 4 ))
        print_clipped "${clear_w}" "${line}"
        (( row++ ))
    done

    render_setup_model_info_box
}

render_setup_size_warning_box() {
    [[ "${SETUP_MODE}" == "modify" ]] || return 0
    current_size_selection_removes_installed || return 0

    local top="$1" left="$2" width="$3"
    local msg="Unchecked installed sizes will be removed"
    local box_h=3
    local box_w=$(( ${#msg} + 12 ))
    (( box_w > width )) && box_w=${width}
    local box_left=$(( left + (width - box_w) / 2 ))

    (( top + box_h > LINES - 5 )) && return 0

    draw_round_box "${top}" "${box_left}" "${box_h}" "${box_w}"
    move $(( top + 1 )) $(( box_left + (box_w - ${#msg}) / 2 ))
    printf '%s' "${msg}"
}

clear_setup_size_warning_region() {
    local top="$1" left="$2" width="$3" r
    for (( r = 0; r < 4; r++ )); do
        move $(( top + r )) "${left}"
        printf '%*s' "${width}" ''
    done
}

render_setup_sizes() {
    local m="${MULTI_SIZE_SELECTED[$SETUP_SIZE_STAGE]}"
    local -a sizes
    IFS='|' read -ra sizes <<< "${MODEL_SIZES[$m]}"

    local W; W="$(setup_box_width 100)"
    local H=$(( ${#sizes[@]} + 13 ))
    (( H < 17 )) && H=17
    local T=$(( (LINES - H) / 2 )) L=$(( (COLS - W) / 2 ))
    draw_round_box "${T}" "${L}" "${H}" "${W}"

    local row=$(( T + 2 )) i marker checked line progress_label
    progress_label="$(( SETUP_SIZE_STAGE + 1 )) of ${#MULTI_SIZE_SELECTED[@]}"
    move "${row}" $(( L + 3 ))
    print_clipped $(( W - ${#progress_label} - 8 )) 'The following models have multiple sizes to choose from'
    move "${row}" $(( L + W - ${#progress_label} - 3 ))
    printf '%s' "${progress_label}"
    draw_hline $(( T + 3 )) "${L}" "${W}"

    row=$(( T + 5 ))
    move "${row}" $(( L + 3 )); printf 'Model: %s' "${MODEL_NAMES[$m]}"
    (( row += 2 ))

    for i in "${!sizes[@]}"; do
        checked='[ ]'
        [[ "${SETUP_SIZE_SELECTED["${m}|${i}"]:-0}" == "1" ]] && checked='[x]'
        marker='  '
        (( SIZE_MENU_IDX == i )) && marker='▶ '
        line="$(format_size_entry "${sizes[$i]}")"
        move "${row}" $(( L + 4 ))
        print_clipped $(( W - 8 )) "${marker}${checked}  $(( i + 1 )). ${line}"
        (( row++ ))
    done

    row=$(( T + H - 4 ))
    if [[ -n "${SETUP_ERR}" ]]; then
        move "${row}" $(( L + 3 )); print_clipped $(( W - 6 )) "${SETUP_ERR}"
    fi
    move $(( T + H - 2 )) $(( L + 3 ))
    print_clipped $(( W - 6 )) 'space toggles, a toggles all, ↵ continues'

    clear_setup_size_warning_region $(( T + H + 1 )) "${L}" "${W}"
    render_setup_size_warning_box $(( T + H + 1 )) "${L}" "${W}"
    render_setup_installation_box
}

render_setup_sizes_list_only() {
    COLS=$(tput cols)
    LINES=$(tput lines)

    (( COLS < MIN_COLS || LINES < MIN_LINES )) && return

    local m="${MULTI_SIZE_SELECTED[$SETUP_SIZE_STAGE]}"
    local -a sizes
    IFS='|' read -ra sizes <<< "${MODEL_SIZES[$m]}"

    local W; W="$(setup_box_width 100)"
    local H=$(( ${#sizes[@]} + 13 ))
    (( H < 17 )) && H=17
    local T=$(( (LINES - H) / 2 )) L=$(( (COLS - W) / 2 ))
    local row=$(( T + 7 )) i marker checked line clear_w
    clear_w=$(( W - 8 ))

    for i in "${!sizes[@]}"; do
        checked='[ ]'
        [[ "${SETUP_SIZE_SELECTED["${m}|${i}"]:-0}" == "1" ]] && checked='[x]'
        marker='  '
        (( SIZE_MENU_IDX == i )) && marker='▶ '
        line="$(format_size_entry "${sizes[$i]}")"

        move "${row}" $(( L + 4 ))
        printf '%*s' "${clear_w}" ''
        move "${row}" $(( L + 4 ))
        print_clipped "${clear_w}" "${marker}${checked}  $(( i + 1 )). ${line}"
        (( row++ ))
    done

    clear_setup_size_warning_region $(( T + H + 1 )) "${L}" "${W}"
    render_setup_size_warning_box $(( T + H + 1 )) "${L}" "${W}"
}

render_setup_confirm() {
    local W; W="$(setup_box_width 104)"
    local H=20
    local T=$(( (LINES - H) / 2 )) L=$(( (COLS - W) / 2 ))
    draw_round_box "${T}" "${L}" "${H}" "${W}"

    local row=$(( T + 2 )) m summary line
    move "${row}" $(( L + 3 )); printf 'Confirm setup'
    draw_hline $(( T + 3 )) "${L}" "${W}"

    row=$(( T + 5 ))
    move "${row}" $(( L + 3 )); printf 'Save directory:'
    (( row++ ))
    move "${row}" $(( L + 5 )); print_clipped $(( W - 8 )) "${SETUP_PLANTBENCH_DIR}"
    (( row += 2 ))

    move "${row}" $(( L + 3 )); printf 'Models and sizes:'
    (( row++ ))
    for m in "${SELECTED_MODELS[@]}"; do
        summary="$(selected_size_summary "${m}")"
        printf -v line '> %-11s  sizes: %s' "${MODEL_NAMES[$m]}" "${summary}"
        move "${row}" $(( L + 5 ))
        print_clipped $(( W - 8 )) "${line}"
        (( row++ ))
    done

    draw_hline $(( T + H - 4 )) "${L}" "${W}"
    move $(( T + H - 2 )) $(( L + 3 ))
    printf 'Proceed with installation?  y / n'
    render_setup_installation_box
}

setup_running_geometry() {
    local __prefix="$1"
    local W=$(( COLS - 8 ))
    (( W > 110 )) && W=110
    (( W < 70 )) && W=70
    (( W > COLS - 4 )) && W=$(( COLS - 4 ))

    local H=$(( LINES - 6 ))
    (( H < 18 )) && H=18
    (( H > LINES - 4 )) && H=$(( LINES - 4 ))

    local T=$(( (LINES - H) / 2 ))
    local L=$(( (COLS - W) / 2 ))
    (( T < 2 )) && T=2
    (( L < 2 )) && L=2

    printf -v "${__prefix}_W" '%d' "${W}"
    printf -v "${__prefix}_H" '%d' "${H}"
    printf -v "${__prefix}_T" '%d' "${T}"
    printf -v "${__prefix}_L" '%d' "${L}"
}

render_setup_running() {
    COLS=$(tput cols)
    LINES=$(tput lines)
    clear_screen
    draw_outer_frame
    render_statusbar

    local G_W G_H G_T G_L
    setup_running_geometry G

    draw_box "${G_T}" "${G_L}" "${G_H}" "${G_W}"

    local row=$(( G_T + 2 ))
    move "${row}" $(( G_L + 3 ))
    printf 'Setup running'

    move "${row}" $(( G_L + G_W - 13 ))
    printf 'please wait'
    draw_hline $(( G_T + 3 )) "${G_L}" "${G_W}"

    SETUP_RUNNING_SCREEN_DRAWN=1

    if [[ "${SETUP_VIEW_MODE}" == "logs" ]]; then
        render_setup_running_logs_only
    else
        render_setup_running_status_only
    fi

    hide_cursor
}

render_setup_running_clear_body() {
    local W="$1" T="$2" L="$3" H="$4"
    local top=$(( T + 5 ))
    local bottom=$(( T + H - 2 ))
    local row
    for (( row = top; row <= bottom; row++ )); do
        move "${row}" $(( L + 3 ))
        printf '%*s' $(( W - 6 )) ''
    done
}

render_setup_running_status_only() {
    [[ "${STATE}" == "setup_running" ]] || return
    [[ "${SETUP_VIEW_MODE}" == "status" ]] || return

    COLS=$(tput cols)
    LINES=$(tput lines)

    (( COLS < MIN_COLS || LINES < MIN_LINES )) && return

    local G_W G_H G_T G_L
    setup_running_geometry G

    if (( SETUP_RUNNING_SCREEN_DRAWN == 0 )); then
        render_setup_running
        return
    fi

    render_setup_running_clear_body "${G_W}" "${G_T}" "${G_L}" "${G_H}"

    local row=$(( G_T + 5 ))
    local content_w=$(( G_W - 6 ))
    local right_col=$(( G_L + G_W - 6 ))
    local m idx model_name model_status icon spinner step step_status step_icon
    local size_entry size_status size_icon size_label
    local -a size_options=()

    move "${row}" $(( G_L + 3 ))
    print_clipped "${content_w}" "Installing selected models"
    (( row += 2 ))

    for idx in "${!SELECTED_MODELS[@]}"; do
        m="${SELECTED_MODELS[$idx]}"
        model_name="${MODEL_NAMES[$m]}"
        model_status="${SETUP_MODEL_RUN_STATUS[$m]:-pending}"

        case "${model_status}" in
            done) icon='✓' ;;
            current) icon='▶' ;;
            *) icon='○' ;;
        esac

        move "${row}" $(( G_L + 5 ))
        printf '%s  %s' "${icon}" "${model_name}"

        if [[ "${model_status}" == "current" ]]; then
            spinner="$(setup_spinner_char)"
            move "${row}" "${right_col}"
            printf '%s' "${spinner}"

            for step in "Pulling container" "Cloning repo" "Downloading model weights"; do
                (( row++ ))
                step_status="${SETUP_STEP_RUN_STATUS["${m}|${step}"]:-pending}"
                case "${step_status}" in
                    done) step_icon='✓' ;;
                    current) step_icon='▶' ;;
                    skipped) step_icon='-' ;;
                    *) step_icon='○' ;;
                esac
                local step_label
                step_label="$(setup_step_display_label "${step}" "${step_status}")"
                move "${row}" $(( G_L + 9 ))
                printf '%s  %s' "${step_icon}" "${step_label}"

                if [[ "${step}" == "Downloading model weights" && "${SETUP_CURRENT_STEP}" == "Downloading model weights" ]]; then
                    IFS='|' read -ra size_options <<< "${MODEL_SIZES[$m]}"
                    for size_entry in "${size_options[@]}"; do
                        if [[ -n "${SETUP_WEIGHT_SIZE_RUN_STATUS["${m}|${size_entry}"]:-}" ]]; then
                            size_status="${SETUP_WEIGHT_SIZE_RUN_STATUS["${m}|${size_entry}"]}"
                            case "${size_status}" in
                                done) size_icon='✓' ;;
                                current) size_icon='▶' ;;
                                skipped) size_icon='-' ;;
                                *) size_icon='○' ;;
                            esac
                            size_label="$(size_short_label "${size_entry}")"
                            (( row++ ))
                            move "${row}" $(( G_L + 13 ))
                            printf '%s  %s' "${size_icon}" "${size_label}"
                        fi
                    done
                fi
            done

            # Visual breathing room before the next model after the expanded subtree.
            (( row++ ))
        fi

        (( row++ ))
        if (( row >= G_T + G_H - 3 )); then
            break
        fi
    done

    move $(( G_T + G_H - 2 )) $(( G_L + 3 ))
    print_clipped "${content_w}" "Press x to show logs"
    hide_cursor
}

render_setup_running_logs_only() {
    [[ "${STATE}" == "setup_running" ]] || return
    [[ "${SETUP_VIEW_MODE}" == "logs" ]] || return

    COLS=$(tput cols)
    LINES=$(tput lines)

    (( COLS < MIN_COLS || LINES < MIN_LINES )) && return

    local G_W G_H G_T G_L
    setup_running_geometry G

    if (( SETUP_RUNNING_SCREEN_DRAWN == 0 )); then
        render_setup_running
        return
    fi

    render_setup_running_clear_body "${G_W}" "${G_T}" "${G_L}" "${G_H}"

    local log_top=$(( G_T + 5 ))
    local log_bottom=$(( G_T + G_H - 2 ))
    local max_lines=$(( log_bottom - log_top + 1 ))
    local total=${#SETUP_LOG[@]}
    local max_width=$(( G_W - 6 ))
    local line i start out_row

    (( total == 0 )) && return

    start=0
    (( total > max_lines )) && start=$(( total - max_lines ))
    out_row=${log_top}

    for (( i = start; i < total; i++ )); do
        line="${SETUP_LOG[$i]}"
        move "${out_row}" $(( G_L + 3 ))
        print_clipped "${max_width}" "${line}"
        (( out_row++ ))
    done

    hide_cursor
}

render_setup_done() {
    local W; W="$(setup_box_width 100)"
    local H=10
    local T=$(( (LINES - H) / 2 )) L=$(( (COLS - W) / 2 ))
    draw_round_box "${T}" "${L}" "${H}" "${W}"

    local row=$(( T + 2 ))
    move "${row}" $(( L + 3 )); printf 'Setup complete'
    draw_hline $(( T + 3 )) "${L}" "${W}"
    row=$(( T + 5 ))
    move "${row}" $(( L + 3 )); printf 'PlantBench installation is ready.'
    (( row += 2 ))
    move "${row}" $(( L + 3 )); print_clipped $(( W - 6 )) "${PLANTBENCH_DIR}"
    move $(( T + H - 2 )) $(( L + 3 )); printf 'Press any key to return home.'
}

render_setup_error() {
    local W; W="$(setup_box_width 104)"
    local H=10
    local T=$(( (LINES - H) / 2 )) L=$(( (COLS - W) / 2 ))
    draw_round_box "${T}" "${L}" "${H}" "${W}"

    local row=$(( T + 2 ))
    move "${row}" $(( L + 3 )); printf 'Setup error'
    draw_hline $(( T + 3 )) "${L}" "${W}"
    row=$(( T + 5 ))
    move "${row}" $(( L + 3 )); print_clipped $(( W - 6 )) "${SETUP_ERR:-Unknown setup error.}"
    if [[ -s "${SETUP_COMMAND_LOG}" ]]; then
        (( row++ ))
        move "${row}" $(( L + 3 )); print_clipped $(( W - 6 )) "Log: ${SETUP_COMMAND_LOG}"
    fi
    move $(( T + H - 2 )) $(( L + 3 )); printf 'Press any key to return home.'
}

MIN_COLS=50
MIN_LINES=28

render_too_small() {
    clear_screen
    move 1 1; printf '┌'
    move 1 2; printf '─── PlantBench ───'
    local msg1="Terminal too small to render."
    local msg2="Minimum: ${MIN_COLS} cols × ${MIN_LINES} lines"
    local msg3="Current: ${COLS} cols × ${LINES} lines"
    move 3 3; printf '%s' "${msg1}"
    move 4 3; printf '%s' "${msg2}"
    move 5 3; printf '%s' "${msg3}"
    move 7 3; printf 'Resize the terminal or press q to quit.'
}

render() {
    COLS=$(tput cols)
    LINES=$(tput lines)

    if (( COLS < MIN_COLS || LINES < MIN_LINES )); then
        render_too_small
        return
    fi

    clear_screen
    draw_outer_frame
    render_statusbar

    case "${STATE}" in
        home)
            if detect_install; then
                render_install_found
            else
                render_no_install
            fi
            ;;
        manual_input)
            if detect_install; then render_install_found; else render_no_install; fi
            render_manual_input
            ;;
        main_stub) render_main_stub ;;
        setup_save_dir) render_setup_save_dir ;;
        setup_existing_install) render_setup_existing_install ;;
        setup_removing_install) render_setup_removing_install ;;
        setup_models) render_setup_models ;;
        setup_sizes) render_setup_sizes ;;
        setup_confirm) render_setup_confirm ;;
        setup_running) render_setup_running ;;
        setup_done) render_setup_done ;;
        setup_error) render_setup_error ;;
    esac
}

# ─── Main loop ────────────────────────────────────────────────────────────────

render
WINCH_FLAG=0
trap 'WINCH_FLAG=1' WINCH

while true; do
    read_key

    # Resize: SIGWINCH sets the flag; polling catches terminals that don't interrupt read
    if [[ "${WINCH_FLAG}" == 1 ]]; then
        WINCH_FLAG=0; render; continue
    fi

    # Timeout with no keypress — just loop
    [[ "${KEY_TIMEOUT}" == 1 ]] && continue

    # q quits from anywhere in the TUI.
    [[ "${KEY}" == "q" ]] && exit 0

    case "${STATE}" in

        home)
            case "${KEY}" in
                $'\033[A'|k)   # up
                    if detect_install; then
                        MAIN_MENU_IDX=$(( MAIN_MENU_IDX > 0 ? MAIN_MENU_IDX - 1 : 0 ))
                        render_installed_menu_only
                        continue
                    else
                        MENU_IDX=$(( MENU_IDX > 0 ? MENU_IDX - 1 : 0 ))
                        render_no_install_menu_only
                        continue
                    fi
                    ;;
                $'\033[B'|j)   # down
                    if detect_install; then
                        MAIN_MENU_MAX=$(( ${#MAIN_MENU[@]} - 1 ))
                        MAIN_MENU_IDX=$(( MAIN_MENU_IDX < MAIN_MENU_MAX ? MAIN_MENU_IDX + 1 : MAIN_MENU_MAX ))
                        render_installed_menu_only
                        continue
                    else
                        MENU_MAX=$(( ${#NO_INSTALL_MENU[@]} - 1 ))
                        MENU_IDX=$(( MENU_IDX < MENU_MAX ? MENU_IDX + 1 : MENU_MAX ))
                        render_no_install_menu_only
                        continue
                    fi
                    ;;
                ''|$'\n')      # enter
                    if detect_install; then
                        case "${MAIN_MENU_IDX}" in
                            0) MAIN_STUB_TITLE="Evaluate on example FASTA"; STATE="main_stub" ;;
                            1) MAIN_STUB_TITLE="Evaluate on custom FASTA"; STATE="main_stub" ;;
                            2) start_modify_setup ;;
                            3) STATE="manual_input"; MANUAL_INPUT=""; MANUAL_ERR="" ;;
                            4) exit 0 ;;
                        esac
                    else
                        case "${MENU_IDX}" in
                            0) start_setup ;;
                            1) STATE="manual_input"; MANUAL_INPUT=""; MANUAL_ERR="" ;;
                            2) exit 0 ;;
                        esac
                    fi
                    ;;
                q) exit 0 ;;
            esac
            ;;

        main_stub)
            STATE="home"
            ;;

        manual_input)
            case "${KEY}" in
                $'')       # escape — cancel
                    STATE="home"; hide_cursor
                    ;;
                $''|$'') # backspace
                    MANUAL_INPUT="${MANUAL_INPUT%?}"; MANUAL_ERR=""
                    render_manual_input_only
                    continue
                    ;;
                ''|$'
')      # enter — apply path
                    if [[ -z "${MANUAL_INPUT}" ]]; then
                        MANUAL_ERR="Path cannot be empty."
                        render_manual_input_only
                        continue
                    else
                        CANDIDATE="${MANUAL_INPUT/#\~/$HOME}"
                        if [[ ! -d "${CANDIDATE}" ]]; then
                            MANUAL_ERR="Directory not found: ${CANDIDATE}"
                            render_manual_input_only
                            continue
                        else
                            PLANTBENCH_DIR="${CANDIDATE}"
                            STATE="home"; MENU_IDX=0; hide_cursor
                        fi
                    fi
                    ;;
                *)
                    # Append printable characters only
                    if [[ "${#KEY}" == 1 && "${KEY}" > $'' ]]; then
                        MANUAL_INPUT+="${KEY}"; MANUAL_ERR=""
                        render_manual_input_only
                        continue
                    fi
                    ;;
            esac
            ;;

        setup_save_dir)
            case "${KEY}" in
                $'\033') STATE="home"; hide_cursor ;;
                $'\177'|$'\b')
                    SETUP_SAVE_INPUT="${SETUP_SAVE_INPUT%?}"
                    render_setup_save_dir_input_only
                    continue
                    ;;
                ''|$'\n') setup_apply_save_dir; hide_cursor ;;
                *)
                    if [[ "${#KEY}" == 1 && "${KEY}" > $'\x1f' ]]; then
                        SETUP_SAVE_INPUT+="${KEY}"
                        render_setup_save_dir_input_only
                        continue
                    fi
                    ;;
            esac
            ;;

        setup_existing_install)
            case "${KEY}" in
                $'\033')
                    STATE="setup_save_dir"
                    SETUP_ERR=""
                    ;;
                $'\033[A'|k)
                    SETUP_EXISTING_MENU_IDX=$(( SETUP_EXISTING_MENU_IDX > 0 ? SETUP_EXISTING_MENU_IDX - 1 : 0 ))
                    render_setup_existing_install_menu_only
                    continue
                    ;;
                $'\033[B'|j)
                    SETUP_EXISTING_MENU_IDX=$(( SETUP_EXISTING_MENU_IDX < 2 ? SETUP_EXISTING_MENU_IDX + 1 : 2 ))
                    render_setup_existing_install_menu_only
                    continue
                    ;;
                ''|$'\n')
                    case "${SETUP_EXISTING_MENU_IDX}" in
                        0)
                            PLANTBENCH_DIR="${SETUP_PLANTBENCH_DIR}"
                            STATE="home"
                            MENU_IDX=0
                            MAIN_MENU_IDX=0
                            hide_cursor
                            ;;
                        1)
                            if perform_existing_install_removal; then
                                SETUP_ERR=""
                                STATE="setup_models"
                                SETUP_MENU_IDX=0
                            else
                                SETUP_ERR="Could not remove existing installation."
                                STATE="setup_existing_install"
                            fi
                            ;;
                        2)
                            STATE="setup_save_dir"
                            SETUP_ERR=""
                            ;;
                    esac
                    ;;
            esac
            ;;

        setup_models)
            case "${KEY}" in
                $'\033') STATE="home" ;;
                $'\033[A'|k)
                    SETUP_MENU_IDX=$(( SETUP_MENU_IDX > 0 ? SETUP_MENU_IDX - 1 : 0 ))
                    render_setup_models_list_only
                    continue
                    ;;
                $'\033[B'|j)
                    SETUP_MENU_IDX=$(( SETUP_MENU_IDX < 5 ? SETUP_MENU_IDX + 1 : 5 ))
                    render_setup_models_list_only
                    continue
                    ;;
                ' ')
                    model_idx=$(( SETUP_MENU_IDX + 1 ))
                    SETUP_MODEL_SELECTED[$model_idx]=$(( 1 - ${SETUP_MODEL_SELECTED[$model_idx]:-0} ))
                    SETUP_ERR=""
                    render_setup_models_list_only
                    continue
                    ;;
                a)
                    setup_toggle_all_models
                    SETUP_ERR=""
                    render_setup_models_list_only
                    continue
                    ;;
                ''|$'\n')
                    build_selected_models
                    if (( ${#SELECTED_MODELS[@]} == 0 )); then
                        SETUP_ERR="Select at least one model."
                    else
                        setup_prepare_size_flow
                    fi
                    ;;
            esac
            ;;

        setup_sizes)
            case "${KEY}" in
                $'\033') STATE="setup_models"; SETUP_ERR="" ;;
                $'\033[A'|k)
                    SIZE_MENU_IDX=$(( SIZE_MENU_IDX > 0 ? SIZE_MENU_IDX - 1 : 0 ))
                    render_setup_sizes_list_only
                    continue
                    ;;
                $'\033[B'|j)
                    current_model="${MULTI_SIZE_SELECTED[$SETUP_SIZE_STAGE]}"
                    IFS='|' read -ra current_sizes <<< "${MODEL_SIZES[$current_model]}"
                    max_idx=$(( ${#current_sizes[@]} - 1 ))
                    SIZE_MENU_IDX=$(( SIZE_MENU_IDX < max_idx ? SIZE_MENU_IDX + 1 : max_idx ))
                    render_setup_sizes_list_only
                    continue
                    ;;
                ' ')
                    current_model="${MULTI_SIZE_SELECTED[$SETUP_SIZE_STAGE]}"
                    key="${current_model}|${SIZE_MENU_IDX}"
                    SETUP_SIZE_SELECTED["${key}"]=$(( 1 - ${SETUP_SIZE_SELECTED[$key]:-0} ))
                    SETUP_ERR=""
                    render_setup_sizes_list_only
                    continue
                    ;;
                a)
                    setup_toggle_all_sizes_for_current_model
                    SETUP_ERR=""
                    render_setup_sizes_list_only
                    continue
                    ;;
                ''|$'\n')
                    if setup_commit_current_sizes; then
                        if (( SETUP_SIZE_STAGE + 1 < ${#MULTI_SIZE_SELECTED[@]} )); then
                            SETUP_SIZE_STAGE=$(( SETUP_SIZE_STAGE + 1 ))
                            SIZE_MENU_IDX=0
                        else
                            STATE="setup_confirm"
                        fi
                    fi
                    ;;
            esac
            ;;

        setup_confirm)
            case "${KEY}" in
                $'\033'|n|N) STATE="home" ;;
                y|Y|''|$'\n')
                    STATE="setup_running"
                    if perform_setup; then
                        STATE="setup_done"
                    else
                        STATE="setup_error"
                    fi
                    ;;
            esac
            ;;

        setup_done|setup_error)
            STATE="home"; MENU_IDX=0; hide_cursor ;;

    esac

    render
done
