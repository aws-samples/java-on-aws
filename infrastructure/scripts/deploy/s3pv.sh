cat <<EOF > ~/environment/unicorn-store-spring/k8s/persistence.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: s3-profiling-pv
spec:
  capacity:
    storage: 1200Gi # ignored, required
  accessModes:
    - ReadWriteMany # supported options: ReadWriteMany / ReadOnlyMany
  mountOptions:
    - allow-other
    - uid=1000
    - gid=1000
    - allow-delete
  csi:
    driver: s3.csi.aws.com # required
    volumeHandle: s3-csi-driver-volume
    volumeAttributes:
      bucketName: $S3PROFILING
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: s3-profiling-pvc
  namespace: unicorn-store-spring
spec:
  accessModes:
    - ReadWriteMany # supported options: ReadWriteMany / ReadOnlyMany
  storageClassName: "" # required for static provisioning
  resources:
    requests:
      storage: 1200Gi # ignored, required
  volumeName: s3-profiling-pv
EOF
