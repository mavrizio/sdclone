#!/bin/bash
# sdimg.sh - riduce o espande il filesystem ext4 dentro un'immagine .img di Raspberry Pi (macOS).
#
#   scripts/sdimg.sh info   IMMAGINE
#   scripts/sdimg.sh shrink IMMAGINE [USCITA]          riduce la rootfs al minimo (stile PiShrink)
#   scripts/sdimg.sh expand IMMAGINE DIMENSIONE [USCITA]   porta l'immagine alla DIMENSIONE (es. 16GB, 14.5GiB, 15931539456)
#
# Non scrive MAI sull'immagine di partenza: crea sempre un file nuovo e rifiuta di sovrascrivere.
# Richiede e2fsprogs:  brew install e2fsprogs
#
# Perche' non si lavora direttamente sul file con "resize2fs file?offset=N": con l'offset resize2fs tronca o
# estende il file in base alla sola dimensione del filesystem, senza contare l'offset, e rovina la coda
# dell'immagine. Qui la partizione viene estratta, ridimensionata da sola e poi ricomposta.
set -euo pipefail

die() { echo "Errore: $*" >&2; exit 1; }

# Pulizia alla chiusura: cartella di lavoro sempre; il file di uscita solo se qualcosa e' andato storto.
WORK=""; OUT_FILE=""; OK=0
cleanup() {
    [ -z "$WORK" ] || rm -rf "$WORK"
    if [ "$OK" != 1 ] && [ -n "$OUT_FILE" ]; then rm -f "$OUT_FILE"; fi
}
trap cleanup EXIT

E2=""
for d in "$(brew --prefix e2fsprogs 2>/dev/null || true)/sbin" /opt/homebrew/opt/e2fsprogs/sbin /usr/local/opt/e2fsprogs/sbin; do
    if [ -x "$d/resize2fs" ]; then E2="$d"; break; fi
done
[ -n "$E2" ] || die "e2fsprogs non trovato. Installalo con:  brew install e2fsprogs"

# Stampa: <numero> <settore iniziale> <settori> dell'ULTIMA partizione, che deve essere Linux (0x83) su MBR.
part_info() {
python3 -I - "$1" <<'PY'
import sys, struct
with open(sys.argv[1], 'rb') as f:
    mbr = f.read(512)
if mbr[510:512] != b'\x55\xaa':
    sys.exit("l'immagine non ha una tabella MBR valida (manca la firma 55AA)")
parts = []
for i in range(4):
    e = mbr[446 + i * 16: 462 + i * 16]
    t = e[4]
    s, n = struct.unpack('<II', e[8:16])
    if t:
        parts.append((i + 1, t, s, n))
if not parts:
    sys.exit("nessuna partizione nella tabella")
if any(t == 0xEE for _, t, _, _ in parts):
    sys.exit("tabella GPT: questo script supporta solo MBR")
num, t, s, n = max(parts, key=lambda p: p[2])
if t != 0x83:
    sys.exit("l'ultima partizione non e' Linux (tipo 0x%02x): non so cosa fare" % t)
print(num, s, n)
PY
}

# Imposta il numero di settori della partizione <n> nell'MBR.
set_sectors() {   # file numero settori
python3 -I - "$1" "$2" "$3" <<'PY'
import sys, struct
path, num, sectors = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(path, 'r+b') as f:
    mbr = bytearray(f.read(512))
    e = 446 + (num - 1) * 16
    mbr[e + 12:e + 16] = struct.pack('<I', sectors)
    f.seek(0)
    f.write(mbr)
PY
}

# Converte "16GB", "14.5GiB", "512MiB" o un numero di byte in byte.
parse_size() {
python3 -I - "$1" <<'PY'
import re, sys
m = re.fullmatch(r'\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB|TB|KIB|MIB|GIB|TIB)?\s*', sys.argv[1].upper())
if not m:
    sys.exit("dimensione non valida: %r (esempi: 16GB, 14.5GiB, 15931539456)" % sys.argv[1])
mult = {None: 1, 'B': 1, 'KB': 10**3, 'MB': 10**6, 'GB': 10**9, 'TB': 10**12,
        'KIB': 2**10, 'MIB': 2**20, 'GIB': 2**30, 'TIB': 2**40}[m.group(2)]
print(int(float(m.group(1)) * mult))
PY
}

human() { python3 -I -c "import sys; b=int(sys.argv[1]); print('%.2f GiB (%d byte)'%(b/2**30,b))" "$1"; }

fsck_ok() {   # file [offset]  -> controlla in sola lettura; ok se esce con 0
    local target="$1"
    "$E2/e2fsck" -fn "$target" > /dev/null 2>&1
}

# dd con il blocco piu' grande possibile: <in> <out> <settore iniziale in> <settore iniziale out> <settori> [conv]
copy_sectors() {
    local in="$1" out="$2" sin="$3" sout="$4" n="$5" conv="${6:-}"
    local bs=512 div=1
    if (( sin % 2048 == 0 && sout % 2048 == 0 && n % 2048 == 0 )); then bs=1m; div=2048
    elif (( sin % 8 == 0 && sout % 8 == 0 && n % 8 == 0 )); then bs=4096; div=8; fi
    dd if="$in" of="$out" bs=$bs skip=$((sin / div)) seek=$((sout / div)) count=$((n / div)) ${conv:+conv=$conv} 2> /dev/null
}

load_info() {   # IMG -> PNUM START SECT
    [ -f "$1" ] || die "file non trovato: $1"
    local out
    out=$(part_info "$1") || die "impossibile leggere la tabella delle partizioni"
    read -r PNUM START SECT <<< "$out"
    (( START % 8 == 0 )) || die "la partizione non e' allineata a 4 KiB (settore iniziale $START)"
    (( SECT % 8 == 0 )) || die "la dimensione della partizione non e' multipla di 4 KiB ($SECT settori)"
}

check_free() {   # cartella byte-necessari
    local free_kb
    free_kb=$(df -k "$1" | awk 'NR==2 {print $4}')
    (( free_kb * 1024 > $2 )) || die "spazio insufficiente in $1: servono circa $(human "$2"), liberi $(human $((free_kb * 1024)))"
}

cmd_info() {
    local img="$1"
    load_info "$img"
    echo "File:                $img"
    echo "Dimensione file:     $(human "$(stat -f %z "$img")")"
    echo "Ultima partizione:   n. $PNUM, inizio settore $START (offset $((START * 512)) byte), $SECT settori = $(human $((SECT * 512)))"
    local off=$((START * 512))
    echo "--- Filesystem (sola lettura):"
    "$E2/e2fsck" -fn "$img?offset=$off" 2>&1 | tail -1
    "$E2/resize2fs" -P "$img?offset=$off" 2>&1 | tail -1
    echo "(il minimo e' in blocchi da 4 KiB; il file ridotto sara' circa: $(human $(( off + $("$E2/resize2fs" -P "$img?offset=$off" 2>&1 | awk '/minimum size/ {print $NF}') * 4096 ))))"
}

build_output() {   # IMG OUT PART NEWSECT   -> compone OUT = [prime START*512 byte di IMG] + PART, aggiorna MBR
    local img="$1" out="$2" part="$3" newsect="$4"
    : > "$out"
    copy_sectors "$img" "$out" 0 0 "$START"
    copy_sectors "$part" "$out" 0 "$START" "$newsect" notrunc
    python3 -I -c "import os,sys; os.truncate(sys.argv[1], int(sys.argv[2]))" "$out" $(( (START + newsect) * 512 ))
    set_sectors "$out" "$PNUM" "$newsect"
}

fsck_repair() {   # file
    local rc=0
    "$E2/e2fsck" -fy "$1" > /dev/null 2>&1 || rc=$?
    (( rc <= 1 )) || die "e2fsck ha trovato errori che non ha saputo correggere (codice $rc) su $1"
}

cmd_shrink() {
    local img="$1" out="${2:-${1%.img}.min.img}"
    load_info "$img"
    [ ! -e "$out" ] || die "$out esiste gia': non lo sovrascrivo"
    local dir; dir=$(cd "$(dirname "$out")" && pwd)
    check_free "$dir" $(( SECT * 512 * 2 ))
    WORK=$(mktemp -d "$dir/.sdimg.XXXXXX"); OUT_FILE="$out"
    local part="$WORK/part.img"

    echo "1/5 Estraggo la partizione ($(human $((SECT * 512))))..."
    copy_sectors "$img" "$part" "$START" 0 "$SECT"
    echo "2/5 Controllo il filesystem..."
    fsck_repair "$part"
    echo "3/5 Riduco al minimo..."
    "$E2/resize2fs" -M "$part" 2>&1 | tail -1
    local fsbytes newsect
    fsbytes=$(stat -f %z "$part")
    newsect=$(( (fsbytes / 512 + 2047) / 2048 * 2048 ))        # arrotondato al MiB
    (( newsect <= SECT )) || die "il filesystem non si puo' ridurre"
    python3 -I -c "import os,sys; os.truncate(sys.argv[1], int(sys.argv[2]))" "$part" $(( newsect * 512 ))
    echo "4/5 Compongo $out..."
    build_output "$img" "$out" "$part" "$newsect"
    rm -f "$part"
    echo "5/5 Verifico..."
    fsck_ok "$out?offset=$((START * 512))" || die "e2fsck non e' pulito sul risultato"
    [ "$(stat -f %z "$out")" = $(( (START + newsect) * 512 )) ] || die "dimensione del file inattesa"
    OK=1
    echo "Fatto: $(human "$(stat -f %z "$img")")  ->  $(human "$(stat -f %z "$out")")"
    echo "       $out"
    echo "Nota: l'immagine ridotta NON si riespande da sola. Dopo l'avvio sul Raspberry: sudo raspi-config nonint do_expand_rootfs && sudo reboot"
}

cmd_expand() {
    local img="$1" total; total=$(parse_size "$2") || exit 1
    local out="${3:-${1%.img}.expanded.img}"
    load_info "$img"
    (( total % 512 == 0 )) || total=$(( total / 512 * 512 ))
    local current_end=$(( (START + SECT) * 512 ))
    (( total > current_end )) || die "la dimensione richiesta ($(human "$total")) non supera quella attuale ($(human "$current_end"))"
    local newsect=$(( (total / 512 - START) / 8 * 8 ))          # multiplo di 4 KiB
    [ ! -e "$out" ] || die "$out esiste gia': non lo sovrascrivo"
    local dir; dir=$(cd "$(dirname "$out")" && pwd)
    check_free "$dir" $(( (SECT + newsect) * 512 + START * 512 + 1073741824 ))
    WORK=$(mktemp -d "$dir/.sdimg.XXXXXX"); OUT_FILE="$out"
    local part="$WORK/part.img"

    echo "1/5 Estraggo la partizione ($(human $((SECT * 512))))..."
    copy_sectors "$img" "$part" "$START" 0 "$SECT"
    echo "2/5 Controllo il filesystem..."
    fsck_repair "$part"
    echo "3/5 Allargo a $(human $((newsect * 512)))..."
    python3 -I -c "import os,sys; os.truncate(sys.argv[1], int(sys.argv[2]))" "$part" $(( newsect * 512 ))
    "$E2/resize2fs" "$part" 2>&1 | tail -1
    echo "4/5 Compongo $out..."
    build_output "$img" "$out" "$part" "$newsect"
    rm -f "$part"
    echo "5/5 Verifico..."
    fsck_ok "$out?offset=$((START * 512))" || die "e2fsck non e' pulito sul risultato"
    [ "$(stat -f %z "$out")" = $(( (START + newsect) * 512 )) ] || die "dimensione del file inattesa"
    OK=1
    echo "Fatto: $(human "$(stat -f %z "$img")")  ->  $(human "$(stat -f %z "$out")")"
    echo "       $out"
    echo "Ricorda: la scheda su cui lo scrivi deve avere almeno $(human "$(stat -f %z "$out")")."
}

case "${1:-}" in
    info)   [ $# -eq 2 ] || die "uso: sdimg.sh info IMMAGINE"; cmd_info "$2" ;;
    shrink) [ $# -ge 2 ] && [ $# -le 3 ] || die "uso: sdimg.sh shrink IMMAGINE [USCITA]"; cmd_shrink "$2" "${3:-}" ;;
    expand) [ $# -ge 3 ] && [ $# -le 4 ] || die "uso: sdimg.sh expand IMMAGINE DIMENSIONE [USCITA]"; cmd_expand "$2" "$3" "${4:-}" ;;
    *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 64 ;;
esac
