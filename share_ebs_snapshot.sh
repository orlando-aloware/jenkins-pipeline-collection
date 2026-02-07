# Take snapshot of volumes
aws ec2 create-snapshot \
  --volume-id vol-0c76fe2d75dd7b00c \
  --description "temp-clone-root-$(date +%F)"
aws ec2 create-snapshot \
  --volume-id vol-00173b35c9d94a8f4 \
  --description "temp-clone-data-$(date +%F)"


aws ec2 modify-snapshot-attribute \
  --snapshot-id snap-XXXX \
  --attribute createVolumePermission \
  --operation-type add \
  --user-ids <YOUR_ACCOUNT_ID>