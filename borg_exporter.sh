#!/bin/bash

set -eu

source /etc/borg_exporter.rc

PROM_FILE=$TEXTFILE_COLLECTOR_DIR/borg.prom

TMP_FILE=$PROM_FILE.$$
[ -e $TMP_FILE ] && rm -f $TMP_FILE

HOSTNAME=$(hostname)
ARCHIVES=$(BORG_PASSPHRASE="$BORG_PASSPHRASE" borg list "$REPOSITORY")
COUNTER=0

[ -e "$TEXTFILE_COLLECTOR_DIR" ] || mkdir -p "$TEXTFILE_COLLECTOR_DIR"

COUNTER=$(echo "$ARCHIVES" | wc -l)
LAST_ARCHIVE=$(BORG_PASSPHRASE="$BORG_PASSPHRASE" borg list --last 1 "$REPOSITORY" | sort -nr | head -n 1)
LAST_ARCHIVE_NAME=$(echo $LAST_ARCHIVE | awk '{print $1}')
LAST_ARCHIVE_DATE=$(echo $LAST_ARCHIVE | awk '{print $3" "$4}')
LAST_ARCHIVE_TIMESTAMP=$(date -d "$LAST_ARCHIVE_DATE" +"%s")
CURRENT_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
NB_HOUR_FROM_LAST_BCK=$(dateutils.ddiff "$LAST_ARCHIVE_DATE" "$CURRENT_DATE" -f '%H')

BORG_EXTRACT_EXIT_CODE=$(BORG_PASSPHRASE="$BORG_PASSPHRASE" borg extract --dry-run "$REPOSITORY::$LAST_ARCHIVE_NAME" > /dev/null 2>&1; echo $?)
BORG_INFO=$(BORG_PASSPHRASE="$BORG_PASSPHRASE" borg info "$REPOSITORY::$LAST_ARCHIVE_NAME")

{
  echo "# HELP borg_last_archive_timestamp Time of last borg backup"
  echo "# TYPE borg_last_archive_timestamp gauge"
  echo "borg_last_archive_timestamp{host=\"${HOSTNAME}\"} $LAST_ARCHIVE_TIMESTAMP"
  echo "# HELP borg_extract_exit_code Borg exit code" 
  echo "# TYPE borg_extract_exit_code gauge"
  echo "borg_extract_exit_code{host=\"${HOSTNAME}\"} $BORG_EXTRACT_EXIT_CODE"
  echo "# HELP borg_hours_from_last_archive Hours since last backup" 
  echo "# TYPE borg_hours_from_last_archive gauge"
  echo "borg_hours_from_last_archive{host=\"${HOSTNAME}\"} $NB_HOUR_FROM_LAST_BCK"
  echo "# HELP borg_archives_count Number of archives" 
  echo "# TYPE borg_archives_count gauge"
  echo "borg_archives_count{host=\"${HOSTNAME}\"} $COUNTER"
  echo "# HELP borg_files_count Number of files" 
  echo "# TYPE borg_files_count gauge"
  echo "borg_files_count{host=\"${HOSTNAME}\"} $(echo "$BORG_INFO" | grep "Number of files" | awk '{print $4}')"
  echo "# HELP borg_chunks_unique Number of unique chunks" 
  echo "# TYPE borg_chunks_unique gauge"
  echo "borg_chunks_unique{host=\"${HOSTNAME}\"} $(echo "$BORG_INFO" | grep "Chunk index" | awk '{print $3}')"
  echo "# HELP borg_chunks_total Total number of chunks" 
  echo "# TYPE borg_chunks_total gauge"
  echo "borg_chunks_total{host=\"${HOSTNAME}\"} $(echo "$BORG_INFO" | grep "Chunk index" | awk '{print $4}')"
} >> $TMP_FILE

function calc_bytes {
  NUM=$1
  UNIT=$2

  case "$UNIT" in
    B)
      echo $NUM
      ;;
    kB)
      echo $NUM | awk '{ print $1 * 1024 }'
      ;;
    MB)
      echo $NUM | awk '{ print $1 * 1024 * 1024 }'
      ;;
    GB)
      echo $NUM | awk '{ print $1 * 1024 * 1024 * 1024 }'
      ;;
    TB)
      echo $NUM | awk '{ print $1 * 1024 * 1024 * 1024 * 1024 }'
      ;;
  esac
}

# byte size
LAST_SIZE=$(calc_bytes $(echo "$BORG_INFO" | grep "This archive" | awk '{print $3}') $(echo "$BORG_INFO" | grep "This archive" | awk '{print $4}'))
LAST_SIZE_COMPRESSED=$(calc_bytes $(echo "$BORG_INFO" | grep "This archive" | awk '{print $5}') $(echo "$BORG_INFO" | grep "This archive" | awk '{print $6}'))
LAST_SIZE_DEDUP=$(calc_bytes $(echo "$BORG_INFO" | grep "This archive" | awk '{print $7}') $(echo "$BORG_INFO" | grep "This archive" | awk '{print $8}'))
TOTAL_SIZE=$(calc_bytes $(echo "$BORG_INFO" | grep "All archives" | awk '{print $3}') $(echo "$BORG_INFO" | grep "All archives" | awk '{print $4}'))
TOTAL_SIZE_COMPRESSED=$(calc_bytes $(echo "$BORG_INFO" | grep "All archives" | awk '{print $5}') $(echo "$BORG_INFO" | grep "All archives" | awk '{print $6}'))
TOTAL_SIZE_DEDUP=$(calc_bytes $(echo "$BORG_INFO" | grep "All archives" | awk '{print $7}') $(echo "$BORG_INFO" | grep "All archives" | awk '{print $8}'))

{
  echo "# HELP borg_last_size Total number of chunks" 
  echo "# TYPE borg_last_size gauge"
  echo "borg_last_size{host=\"${HOSTNAME}\"} $LAST_SIZE"
  echo "# HELP borg_last_size_compressed Total number of chunks" 
  echo "# TYPE borg_last_size_compressed gauge"
  echo "borg_last_size_compressed{host=\"${HOSTNAME}\"} $LAST_SIZE_COMPRESSED"
  echo "# HELP borg_last_size_dedup Total number of chunks" 
  echo "# TYPE borg_last_size_dedup gauge"
  echo "borg_last_size_dedup{host=\"${HOSTNAME}\"} $LAST_SIZE_DEDUP"
  echo "# HELP borg_total_size Total number of chunks" 
  echo "# TYPE borg_total_size gauge"
  echo "borg_total_size{host=\"${HOSTNAME}\"} $TOTAL_SIZE"
  echo "# HELP borg_total_size_compressed Total number of chunks" 
  echo "# TYPE borg_total_size_compressed gauge"
  echo "borg_total_size_compressed{host=\"${HOSTNAME}\"} $TOTAL_SIZE_COMPRESSED"
  echo "# HELP borg_total_size_dedup Total number of chunks" 
  echo "# TYPE borg_total_size_dedup gauge"
  echo "borg_total_size_dedup{host=\"${HOSTNAME}\"} $TOTAL_SIZE_DEDUP"
  echo ""
} >> $TMP_FILE

mv -f $TMP_FILE $PROM_FILE
