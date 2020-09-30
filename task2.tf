// mention IAM user in profile
provider "aws" {
  region = "ap-south-1"
  profile = "<IAM User>"
}

// give security group a name eg., sg_group

resource "aws_security_group" "sg_group" {
  name        = "TLS"
  description = "Allow TLS inbound traffic"
  vpc_id      = "<VPC ID>"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg_group"
  }
}

// give the instance a name eg., tfinst

resource "aws_instance" "tfinst" {
  ami = "ami-0447a12f28fddb066"              // provided by Amazon or create one
  instance_type = "<Instance type>"          // eg., t2.micro
  key_name = "<Key Name>"                    // eg., keyos1 (same as above)
  security_groups = [ aws_security_group.sg_group.id ]
  subnet_id = "<Subnet ID>"                  // assigned by AWS
  
  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = file("Key Path")           // file-path of key
    host = aws_instance.tfinst.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
     ]
  }

  tags = {
    Name = "tfinst"
  }
}

resource "aws_efs_file_system" "task2-efs" {
  creation_token = "task2-efs"

  tags = {
    Name = "Task-2-volume"
  }
}

resource "aws_efs_access_point" "efs-access" {
  file_system_id = aws_efs_file_system.task2-efs.id
}

resource "aws_vpc" "task2-vpc-efs" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "task2-subnet" {
  vpc_id            = aws_vpc.task2-vpc-efs.id
  availability_zone = "ap-south-1a"                // mentions the AZ to use
  cidr_block        = "10.0.1.0/24"
}

resource "aws_efs_mount_target" "task2-efs-mount" {
  file_system_id = aws_efs_file_system.task2-efs.id
  subnet_id      = aws_subnet.task2-subnet.id
}

resource "null_resource" "mount_vol" {
  depends_on = [
    aws_efs_mount_target.task2-efs-mount,
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("<Key-Path>")          // file-path of key and name
    host     = aws_instance.tfinst.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mount  ${aws_efs_mount_target.task2-efs-mount.mount_target_dns_name}  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/sarthakSharma5/cloud2.git /workspace",
      "sudo cp -r /workspace/* /var/www/html/",
    ]
  }
}

resource "aws_s3_bucket" "terraform_bucket_task_2" {
  bucket = "task2-tf-efs"                        // give a name to the bucket
  acl = "public-read"
  
  versioning {
    enabled = true
  }
  
  tags = {
    Name = "terraform_bucket_task_2"
    Env = "Dev"
  }
}


resource "aws_s3_bucket_public_access_block" "s3BlockPublicAccess" {
  bucket = aws_s3_bucket.terraform_bucket_task_2.id
  block_public_acls   = true
  block_public_policy = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object" "terraform_bucket_task_2_object" {
  depends_on = [ 
    aws_s3_bucket.terraform_bucket_task_2,
  ]
  bucket = aws_s3_bucket.terraform_bucket_task_2.bucket
  key = "cldcomp.jpg"                      // provide key-name eg., image name
  acl = "public-read"
  source = "<Path of Local_Image>"         // image: cldcomp.jpg
}
// Provide Path of Local Image to upload as an object as value of source

resource "aws_cloudfront_distribution" "terraform_distribution_2" {
  origin {
    domain_name = "cldcomp.jpg"                  // key used for s3 bucket object
    origin_id = "Cloud_comp"

    custom_origin_config {
      http_port = 80
      https_port = 80
      origin_protocol_policy = "match-viewer"
      origin_ssl_protocols = [ "TLSv1", "TLSv1.1", "TLSv1.2" ]
    }
  }

  enabled = true
  default_cache_behavior {
    allowed_methods = [ 
      "DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT",
    ]
    cached_methods = [ "GET", "HEAD" ]
    target_origin_id = "Cloud_comp"             // use same as above for origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl = 0
    default_ttl = 3600
    max_ttl = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}