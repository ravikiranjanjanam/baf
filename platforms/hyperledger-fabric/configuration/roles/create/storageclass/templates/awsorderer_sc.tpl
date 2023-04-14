kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: {{ sc_name }}
provisioner: ebs.csi.aws.com
parameters:
  type: gp2
  encrypted: "true"
