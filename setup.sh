#!/usr/bin/env bash
# setup.sh — PlantBench dependency setup TUI
#
# Creates a conda environment for PlantBench host-side dependencies:
#   - python
#   - pip
#   - git
#   - Hugging Face CLI / hf
#
# Also checks:
#   - CUDA 12.8 is already loaded/available before doing anything else
#   - apptainer is available, or singularity can be wrapped as apptainer

set -uo pipefail

# ─── Terminal setup / teardown ────────────────────────────────────────────────

cleanup() {
    printf '\033[?25h'    # show cursor
    printf '\033[?1049l'  # leave alternate screen
    stty echo 2>/dev/null || true
}
trap cleanup EXIT INT TERM

printf '\033[?1049h'
printf '\033[?25l'
stty -echo 2>/dev/null || true

COLS=$(tput cols 2>/dev/null || printf '80')
LINES=$(tput lines 2>/dev/null || printf '24')

# ─── Drawing helpers ──────────────────────────────────────────────────────────

move()          { printf '\033[%d;%dH' "$1" "$2"; }
clear_screen()  { printf '\033[2J'; }
show_cursor()   { printf '\033[?25h'; }
hide_cursor()   { printf '\033[?25l'; }

repeat_into() {
    local _var="$1" _str="$2" _n="$3" _out="" i
    (( _n < 0 )) && _n=0
    for (( i = 0; i < _n; i++ )); do _out+="${_str}"; done
    printf -v "${_var}" '%s' "${_out}"
}

draw_box() {
    local top="$1" left="$2" h="$3" w="$4"
    (( h < 2 || w < 4 )) && return 0

    local bottom=$(( top + h - 1 ))
    local right=$(( left + w - 1 ))
    local inner=$(( w - 2 ))
    local hbar

    repeat_into hbar "─" "${inner}"

    move "${top}"    "${left}"; printf '╭%s╮' "${hbar}"
    move "${bottom}" "${left}"; printf '╰%s╯' "${hbar}"

    local r
    for (( r = top + 1; r < bottom; r++ )); do
        move "${r}" "${left}";  printf '│'
        move "${r}" "${right}"; printf '│'
    done
}

draw_hline() {
    local row="$1" left="$2" width="$3"
    (( width < 4 )) && return 0

    local inner=$(( width - 2 ))
    local hbar
    repeat_into hbar "─" "${inner}"
    move "${row}" "${left}"; printf '├%s┤' "${hbar}"
}

draw_outer_frame() {
    COLS=$(tput cols 2>/dev/null || printf '80')
    LINES=$(tput lines 2>/dev/null || printf '24')

    local inner=$(( COLS - 2 ))
    local hbar
    repeat_into hbar "─" "${inner}"

    printf '\033[?7l' # disable autowrap before touching bottom-right cell
    move 1          1; printf '┌%s┐' "${hbar}"
    move "${LINES}" 1; printf '└%s┘' "${hbar}"
    printf '\033[?7h'

    local r
    for (( r = 2; r < LINES; r++ )); do
        move "${r}" 1;         printf '│'
        move "${r}" "${COLS}"; printf '│'
    done
}

print_clipped() {
    local width="$1" text="$2"
    (( width <= 0 )) && return 0
    printf '%.*s' "${width}" "${text}"
}

render_shell() {
    COLS=$(tput cols 2>/dev/null || printf '80')
    LINES=$(tput lines 2>/dev/null || printf '24')

    clear_screen
    draw_outer_frame

    move "${LINES}" 3
    printf 'PlantBench setup'

    local hint="$1"
    move "${LINES}" $(( COLS - ${#hint} - 2 ))
    printf '%s' "${hint}"
}

read_key() {
    local key="" rest=""
    IFS= read -rsn1 key || true
    if [[ "${key}" == $'\033' ]]; then
        IFS= read -rsn2 -t 0.05 rest || true
        key+="${rest:-}"
    fi
    printf '%s' "${key}"
}

pause_exit() {
    local msg="$1"
    render_shell "any key  exit"

    local W=78 H=9
    (( W > COLS - 4 )) && W=$(( COLS - 4 ))
    (( W < 40 )) && W=40

    local T=$(( (LINES - H) / 2 ))
    local L=$(( (COLS - W) / 2 ))
    (( T < 2 )) && T=2
    (( L < 2 )) && L=2

    draw_box "${T}" "${L}" "${H}" "${W}"

    move $(( T + 2 )) $(( L + 3 ))
    printf 'Dependency check failed'
    draw_hline $(( T + 3 )) "${L}" "${W}"

    move $(( T + 5 )) $(( L + 3 ))
    print_clipped $(( W - 6 )) "${msg}"

    move $(( T + H - 2 )) $(( L + 3 ))
    printf 'Press any key to exit'

    read_key >/dev/null
    exit 1
}

# ─── Environment/module helpers ───────────────────────────────────────────────

need() {
    command -v "$1" >/dev/null 2>&1
}

load_modules_init() {
    if ! type module >/dev/null 2>&1; then
        [[ -r /etc/profile.d/modules.sh ]] && source /etc/profile.d/modules.sh 2>/dev/null || true
        [[ -r /usr/share/Modules/init/bash ]] && source /usr/share/Modules/init/bash 2>/dev/null || true
        [[ -r /usr/share/lmod/lmod/init/bash ]] && source /usr/share/lmod/lmod/init/bash 2>/dev/null || true
    fi
}

try_module() {
    local name="$1"
    load_modules_init
    type module >/dev/null 2>&1 && module load "${name}" >/dev/null 2>&1
}

cuda_128_ok() {
    load_modules_init

    local loaded=""
    if type module >/dev/null 2>&1; then
        loaded="$(module list 2>&1 || true)"
        grep -Eq 'cuda/12\.8|cuda-12\.8|CUDA/12\.8' <<< "${loaded}" && return 0
    fi

    [[ "${CUDA_HOME:-}" == *"12.8"* ]] && return 0
    [[ "${CUDA_PATH:-}" == *"12.8"* ]] && return 0

    if need nvcc; then
        nvcc --version 2>/dev/null | grep -Eq 'release 12\.8|V12\.8' && return 0
    fi

    return 1
}

# ─── Setup state ──────────────────────────────────────────────────────────────

ENV_NAME=""
LOG_LINES=()
LOG_FILE="${TMPDIR:-/tmp}/plantbench_host_setup_$$.log"
RUNNING_SCREEN_DRAWN=0

add_log() {
    LOG_LINES+=("$*")
    if (( ${#LOG_LINES[@]} > 200 )); then
        LOG_LINES=("${LOG_LINES[@]: -200}")
    fi

    if (( RUNNING_SCREEN_DRAWN == 1 )); then
        render_running_log_viewport
    else
        render_running
    fi
}

run_logged() {
    local label="$1"
    shift

    add_log "  ${label}"

    if "$@" >>"${LOG_FILE}" 2>&1; then
        add_log "  ✓ ${label}"
        return 0
    fi

    add_log "  ERROR: ${label}"
    return 1
}

# ─── Screens ──────────────────────────────────────────────────────────────────

render_env_prompt() {
    render_shell "↵  continue   q  quit"

    local W=76 H=11
    (( W > COLS - 4 )) && W=$(( COLS - 4 ))
    (( W < 42 )) && W=42

    local T=$(( (LINES - H) / 2 ))
    local L=$(( (COLS - W) / 2 ))
    (( T < 2 )) && T=2
    (( L < 2 )) && L=2

    draw_box "${T}" "${L}" "${H}" "${W}"

    move $(( T + 2 )) $(( L + 3 ))
    printf 'Enter conda environment name'

    draw_hline $(( T + 3 )) "${L}" "${W}"

    move $(( T + 6 )) $(( L + 3 ))
    print_clipped $(( W - 6 )) "> ${ENV_NAME}"

    move $(( T + 8 )) $(( L + 3 ))
    printf 'Default: plantbench'

    show_cursor
    move $(( T + 6 )) $(( L + 5 + ${#ENV_NAME} ))
}

render_env_input_only() {
    COLS=$(tput cols 2>/dev/null || printf '80')
    LINES=$(tput lines 2>/dev/null || printf '24')

    local W=76 H=11
    (( W > COLS - 4 )) && W=$(( COLS - 4 ))
    (( W < 42 )) && W=42

    local T=$(( (LINES - H) / 2 ))
    local L=$(( (COLS - W) / 2 ))
    (( T < 2 )) && T=2
    (( L < 2 )) && L=2

    move $(( T + 6 )) $(( L + 3 ))
    printf '%*s' $(( W - 6 )) ''

    move $(( T + 6 )) $(( L + 3 ))
    print_clipped $(( W - 6 )) "> ${ENV_NAME}"

    show_cursor
    move $(( T + 6 )) $(( L + 5 + ${#ENV_NAME} ))
}

render_running() {
    render_shell "setup running"

    local W=$(( COLS - 8 ))
    (( W > 92 )) && W=92
    (( W < 50 )) && W=50

    local H=$(( LINES - 6 ))
    (( H < 18 )) && H=18

    local T=$(( (LINES - H) / 2 ))
    local L=$(( (COLS - W) / 2 ))
    (( T < 2 )) && T=2
    (( L < 2 )) && L=2

    draw_box "${T}" "${L}" "${H}" "${W}"

    move $(( T + 2 )) $(( L + 3 ))
    printf 'Installing dependencies'

    move $(( T + 2 )) $(( L + W - 18 ))
    printf 'please wait'

    draw_hline $(( T + 3 )) "${L}" "${W}"

    RUNNING_SCREEN_DRAWN=1
    render_running_log_viewport
    hide_cursor
}

render_running_log_viewport() {
    COLS=$(tput cols 2>/dev/null || printf '80')
    LINES=$(tput lines 2>/dev/null || printf '24')

    local W=$(( COLS - 8 ))
    (( W > 92 )) && W=92
    (( W < 50 )) && W=50

    local H=$(( LINES - 6 ))
    (( H < 18 )) && H=18

    local T=$(( (LINES - H) / 2 ))
    local L=$(( (COLS - W) / 2 ))
    (( T < 2 )) && T=2
    (( L < 2 )) && L=2

    local log_top=$(( T + 5 ))
    local log_bottom=$(( T + H - 2 ))
    local max_lines=$(( log_bottom - log_top + 1 ))
    local total=${#LOG_LINES[@]}
    local start=0
    local max_width=$(( W - 6 ))

    (( total > max_lines )) && start=$(( total - max_lines ))

    local row
    for (( row = log_top; row <= log_bottom; row++ )); do
        move "${row}" $(( L + 3 ))
        printf '%*s' "${max_width}" ''
    done

    local i out_row line
    out_row=${log_top}
    for (( i = start; i < total; i++ )); do
        line="${LOG_LINES[$i]}"
        move "${out_row}" $(( L + 3 ))
        print_clipped "${max_width}" "${line}"
        (( out_row++ ))
    done

    hide_cursor
}

render_done() {
    render_shell "any key  exit"

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

    local W=${title_w}
    (( W > COLS - 4 )) && W=$(( COLS - 4 ))

    local title_h=5
    local gap_after_logo=2
    local box_h=19
    local total_h=$(( title_h + gap_after_logo + box_h ))

    local T=$(( (LINES - total_h) / 2 ))
    local L=$(( (COLS - W) / 2 ))
    (( T < 2 )) && T=2
    (( L < 2 )) && L=2

    local title_col=$(( (COLS - title_w) / 2 ))
    local row="${T}"
    local i

    for i in "${!PLANT[@]}"; do
        move "${row}" "${title_col}"
        printf '%-*s   %s' "${plant_w}" "${PLANT[$i]}" "${BENCH[$i]}"
        (( row++ ))
    done

    row=$(( row + gap_after_logo ))

    local box_t="${row}"
    draw_box "${box_t}" "${L}" "${box_h}" "${W}"

    move $(( box_t + 2 )) $(( L + 3 ))
    printf 'Setup complete'

    draw_hline $(( box_t + 3 )) "${L}" "${W}"

    move $(( box_t + 5 )) $(( L + 3 ))
    print_clipped $(( W - 6 )) "Conda environment created: ${ENV_NAME}"

    local label='To use the software, run'
    local activate_cmd="conda activate ${ENV_NAME}"
    local main_cmd='./main.sh'

    local run_box_w=$(( ${#label} + 8 ))
    local command_box_w=$(( ${#activate_cmd} + 8 ))
    (( ${#main_cmd} + 8 > command_box_w )) && command_box_w=$(( ${#main_cmd} + 8 ))

    local max_sub_box_w=$(( W - 10 ))
    (( run_box_w > max_sub_box_w )) && run_box_w="${max_sub_box_w}"
    (( command_box_w > max_sub_box_w )) && command_box_w="${max_sub_box_w}"
    (( run_box_w < 34 )) && run_box_w=34
    (( command_box_w < 34 )) && command_box_w=34

    local run_box_h=3
    local command_box_h=5
    local run_box_t=$(( box_t + 8 ))
    local run_box_l=$(( L + (W - run_box_w) / 2 ))
    local command_box_t=$(( run_box_t + run_box_h ))
    local command_box_l=$(( L + (W - command_box_w) / 2 ))

    draw_box "${run_box_t}" "${run_box_l}" "${run_box_h}" "${run_box_w}"
    move $(( run_box_t + 1 )) $(( run_box_l + (run_box_w - ${#label}) / 2 ))
    printf '%s' "${label}"

    draw_box "${command_box_t}" "${command_box_l}" "${command_box_h}" "${command_box_w}"
    move $(( command_box_t + 1 )) $(( command_box_l + 3 ))
    print_clipped $(( command_box_w - 6 )) "${activate_cmd}"

    draw_hline $(( command_box_t + 2 )) "${command_box_l}" "${command_box_w}"

    move $(( command_box_t + 3 )) $(( command_box_l + 3 ))
    print_clipped $(( command_box_w - 6 )) "${main_cmd}"

    move $(( box_t + box_h - 2 )) $(( L + 3 ))
    printf 'Press any key to exit'
}

render_error() {
    local msg="$1"

    render_shell "any key  exit"

    local W=82 H=11
    (( W > COLS - 4 )) && W=$(( COLS - 4 ))
    (( W < 50 )) && W=50

    local T=$(( (LINES - H) / 2 ))
    local L=$(( (COLS - W) / 2 ))
    (( T < 2 )) && T=2
    (( L < 2 )) && L=2

    draw_box "${T}" "${L}" "${H}" "${W}"

    move $(( T + 2 )) $(( L + 3 ))
    printf 'Setup failed'

    draw_hline $(( T + 3 )) "${L}" "${W}"

    move $(( T + 5 )) $(( L + 3 ))
    print_clipped $(( W - 6 )) "${msg}"

    move $(( T + 7 )) $(( L + 3 ))
    print_clipped $(( W - 6 )) "Log: ${LOG_FILE}"

    move $(( T + H - 2 )) $(( L + 3 ))
    printf 'Press any key to exit'
}

# ─── Dependency setup ─────────────────────────────────────────────────────────

ensure_conda() {
    if need conda; then
        return 0
    fi

    if [[ -r "${HOME}/miniconda3/etc/profile.d/conda.sh" ]]; then
        source "${HOME}/miniconda3/etc/profile.d/conda.sh" 2>/dev/null || true
        need conda && return 0
    fi

    if [[ -r "${HOME}/anaconda3/etc/profile.d/conda.sh" ]]; then
        source "${HOME}/anaconda3/etc/profile.d/conda.sh" 2>/dev/null || true
        need conda && return 0
    fi

    try_module conda
    need conda && return 0

    try_module miniconda
    need conda && return 0

    try_module anaconda
    need conda && return 0

    return 1
}

create_conda_env() {
    if conda env list 2>/dev/null | awk '{print $1}' | grep -Fxq "${ENV_NAME}"; then
        add_log "Conda environment '${ENV_NAME}' already exists"
        return 0
    fi

    run_logged "create conda environment '${ENV_NAME}'" \
        conda create -y -n "${ENV_NAME}" -c conda-forge python=3.11 pip git
}

install_hf() {
    run_logged "install Hugging Face CLI" \
        conda run -n "${ENV_NAME}" python -m pip install --upgrade "huggingface_hub[cli]"
}

ensure_apptainer() {
    if need apptainer; then
        add_log "apptainer found: $(command -v apptainer)"
        return 0
    fi

    try_module apptainer
    if need apptainer; then
        add_log "apptainer loaded via module: $(command -v apptainer)"
        return 0
    fi

    try_module singularity
    if need singularity; then
        mkdir -p "${HOME}/.local/bin"
        cat > "${HOME}/.local/bin/apptainer" <<'EOWRAP'
#!/usr/bin/env bash
exec singularity "$@"
EOWRAP
        chmod +x "${HOME}/.local/bin/apptainer"
        export PATH="${HOME}/.local/bin:${PATH}"
        add_log "created apptainer wrapper around singularity"
        return 0
    fi

    return 1
}

make_main_executable() {
    if [[ -f main.sh ]]; then
        chmod +x main.sh
        add_log "made main.sh executable"
    fi

    if [[ -f plantbench.sh ]]; then
        chmod +x plantbench.sh
        add_log "made plantbench.sh executable"
    fi
}

run_setup() {
    LOG_LINES=()
    RUNNING_SCREEN_DRAWN=0
    : > "${LOG_FILE}" 2>/dev/null || true

    render_running

    add_log "CUDA 12.8: OK"
    add_log "Preparing conda environment: ${ENV_NAME}"

    if ! ensure_conda; then
        render_error "conda was not found. Install Miniconda/Anaconda or load a conda module"
        read_key >/dev/null
        exit 1
    fi

    if ! create_conda_env; then
        render_error "Failed to create conda environment '${ENV_NAME}'"
        read_key >/dev/null
        exit 1
    fi

    if ! install_hf; then
        render_error "Failed to install Hugging Face CLI in '${ENV_NAME}'"
        read_key >/dev/null
        exit 1
    fi

    if ! ensure_apptainer; then
        render_error "apptainer was not found. Try: module load apptainer"
        read_key >/dev/null
        exit 1
    fi

    make_main_executable

    add_log "Done"
    render_done
    read_key >/dev/null
}

# ─── Main ─────────────────────────────────────────────────────────────────────

if ! cuda_128_ok; then
    pause_exit "CUDA 12.8 is required."
fi

render_env_prompt

while true; do
    key="$(read_key)"
    case "${key}" in
        q)
            exit 0
            ;;
        $'\177'|$'\b')
            ENV_NAME="${ENV_NAME%?}"
            render_env_input_only
            ;;
        ''|$'\n')
            ENV_NAME="${ENV_NAME:-plantbench}"
            hide_cursor
            run_setup
            exit 0
            ;;
        *)
            if [[ "${#key}" == 1 && "${key}" > $'\x1f' ]]; then
                ENV_NAME+="${key}"
                render_env_input_only
            fi
            ;;
    esac
done
