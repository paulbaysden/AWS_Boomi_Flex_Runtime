# EFS file system, mount targets, security group, access point, and EFS CSI driver add-on.

resource "aws_security_group" "efs" {
  name        = "${local.efs_name}-efs"
  description = "NFS (2049) from EKS nodes to Boomi Flex Runtime EFS"
  vpc_id      = local.cfg.aws.vpc_id

  ingress {
    description     = "NFS from EKS worker nodes"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [local.cfg.aws.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.efs_name}-efs" })
}

resource "aws_efs_file_system" "flex" {
  creation_token   = local.efs_name
  encrypted        = local.cfg.efs.encrypted
  kms_key_id       = local.cfg.efs.kms_key_id != "" ? local.cfg.efs.kms_key_id : null
  performance_mode = local.cfg.efs.performance_mode
  throughput_mode  = local.cfg.efs.throughput_mode

  tags = merge(local.tags, { Name = local.efs_name })

  # Protects the data from an accidental destroy. Remove this block if you want
  # `terraform destroy` to be able to delete the file system.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_efs_mount_target" "flex" {
  for_each        = toset(local.cfg.aws.subnet_ids)
  file_system_id  = aws_efs_file_system.flex.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

# The access point enforces UID/GID 1000 on the root directory, which the Flex Runtime requires.
resource "aws_efs_access_point" "flex" {
  file_system_id = aws_efs_file_system.flex.id

  posix_user {
    uid = local.cfg.efs.access_point.uid
    gid = local.cfg.efs.access_point.gid
  }

  root_directory {
    path = local.cfg.efs.access_point.path

    creation_info {
      owner_uid   = local.cfg.efs.access_point.uid
      owner_gid   = local.cfg.efs.access_point.gid
      permissions = local.cfg.efs.access_point.permissions
    }
  }

  tags = merge(local.tags, { Name = "${local.efs_name}-ap" })

  depends_on = [aws_efs_mount_target.flex]
}

resource "aws_eks_addon" "efs_csi" {
  count = local.cfg.aws.install_efs_csi_addon ? 1 : 0

  cluster_name                = local.cfg.aws.eks_cluster_name
  addon_name                  = "aws-efs-csi-driver"
  service_account_role_arn    = local.cfg.aws.efs_csi_role_arn != "" ? local.cfg.aws.efs_csi_role_arn : null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}
