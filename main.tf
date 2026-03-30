terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-west-1"
}

resource "aws_vpc" "steakneggs" {
  cidr_block = "10.0.0.0/16"
	enable_dns_hostnames = true
	
	tags = {
		Name = "steakneggs_vpc"
	}
}

resource "aws_subnet" "alb_ecs_public" {
	vpc_id = aws_vpc.steakneggs.id
	cidr_block = "10.0.0.0/24"
	availability_zone = "us-west-1a"
  map_public_ip_on_launch = true
	
	tags = {
		Name = "alb_ecs_public"
	}
}

resource "aws_subnet" "alb_ecs_public_b" {
	vpc_id = aws_vpc.steakneggs.id
	cidr_block = "10.0.1.0/24"
	availability_zone = "us-west-1c"
  map_public_ip_on_launch = true
	
	tags = { 
		Name = "alb_ecs_public_b" 
	}
}	

resource "aws_subnet" "pg_redis_private" {
	vpc_id = aws_vpc.steakneggs.id
	cidr_block = "10.0.2.0/24"
	availability_zone = "us-west-1a"
	
	tags = {
		Name = "pg_redis_private"
	}
}

resource "aws_subnet" "pg_redis_private_unused" {
	vpc_id = aws_vpc.steakneggs.id
	cidr_block = "10.0.3.0/24"
	availability_zone = "us-west-1c"
	
	tags = {
		Name = "pg_redis_private_unused"
	}
}

resource "aws_internet_gateway" "main" {
	vpc_id = aws_vpc.steakneggs.id
}

resource "aws_route_table" "out" {
	vpc_id = aws_vpc.steakneggs.id
	
	route {
		cidr_block = "0.0.0.0/0"
		gateway_id = aws_internet_gateway.main.id
	}
}

resource "aws_route_table_association" "out_a" {
	subnet_id = aws_subnet.alb_ecs_public.id
	route_table_id = aws_route_table.out.id
}

resource "aws_route_table_association" "out_b" {
	subnet_id = aws_subnet.alb_ecs_public_b.id
	route_table_id = aws_route_table.out.id
}

resource "aws_security_group" "alb" {
	name = "steakneggs-alb-sg"
	vpc_id = aws_vpc.steakneggs.id
	
	ingress {
		from_port = 80
		to_port = 80
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}
	
	ingress {
		from_port = 443
		to_port = 443
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}
	
	egress {
		from_port = 0
		to_port = 0
		protocol = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}
}

resource "aws_security_group" "ecs" {
	name = "steakneggs-ecs-sg"
	vpc_id = aws_vpc.steakneggs.id
	
	ingress {
		from_port = 3000
		to_port = 3000
		protocol = "tcp"
		security_groups = [aws_security_group.alb.id]
	}
	
	egress {
		from_port = 0
		to_port = 0
		protocol = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}
}

resource "aws_security_group" "db" {
	name = "steakneggs-db-sg"
	vpc_id = aws_vpc.steakneggs.id
	
	ingress {
		from_port = 5432
		to_port = 5432
		protocol = "tcp"
		security_groups = [aws_security_group.ecs.id]
	}
}

resource "aws_security_group" "redis" {
	name = "steakneggs-redis-sg"
	vpc_id = aws_vpc.steakneggs.id
	
	ingress {
		from_port = 6379
		to_port = 6379
		protocol = "tcp"
		security_groups = [aws_security_group.ecs.id]		
	}
}

resource "aws_db_subnet_group" "main" {
	name = "steakneggs-db-subnets"
	subnet_ids = [aws_subnet.pg_redis_private.id, aws_subnet.pg_redis_private_unused.id]
}

resource "aws_db_instance" "postgres" {
	identifier = "steakneggs-db"
	engine = "postgres"
	engine_version = "17"
	instance_class = "db.t4g.micro"
	allocated_storage = 20
	storage_type = "gp3"
	
	db_name = "steakneggs"
	username = "steakneggs"
	password = var.db_password
	
	db_subnet_group_name = aws_db_subnet_group.main.name
	vpc_security_group_ids = [aws_security_group.db.id]
	
	backup_retention_period = 7
	backup_window = "03:00-04:00"
	
	maintenance_window = "Mon:04:00-Mon:05:00"
	storage_encrypted = true
	
	skip_final_snapshot = false
	final_snapshot_identifier = "steakneggs-db-final"
	deletion_protection = true
	
	performance_insights_enabled = true
	
	tags = {
		Name = "steakneggs-db"
	}
}

resource "aws_elasticache_subnet_group" "main" {
	name = "steakneggs-redis-subnets"
	subnet_ids = [aws_subnet.pg_redis_private.id, aws_subnet.pg_redis_private_unused.id]
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "steakneggs-redis"
  description          = "steakneggs redis"
  engine               = "valkey"
  engine_version       = "8.2"
  node_type            = "cache.t4g.micro"
  num_cache_clusters   = 1
  port                 = 6379

  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]

  transit_encryption_enabled = true

  maintenance_window   = "sat:04:00-sat:05:00"

  tags = {
    Name = "steakneggs-redis"
  }
}

resource "aws_lb" "main" {
	name = "steakneggs-alb"
	security_groups = [aws_security_group.alb.id]
	subnets = [aws_subnet.alb_ecs_public.id, aws_subnet.alb_ecs_public_b.id]
	
	tags = {
		Name = "steakneggs-alb"
	}
}

resource "aws_lb_target_group" "ecs" {
	name = "steakneggs-tg"
	port = 3000
	protocol = "HTTP"
	vpc_id = aws_vpc.steakneggs.id
	
	target_type = "ip"
	
	health_check {
		healthy_threshold = 3
		interval = 30
		matcher = "200"
		path = "/"
		timeout = 5
		unhealthy_threshold = 5
	}
	
	tags = {
		Name = "steakneggs-tg"
	}
}

data "aws_acm_certificate" "main" {
  domain   = "www.steakneggs.art"
  statuses = ["ISSUED"]
}

resource "aws_lb_listener" "https" {
	load_balancer_arn = aws_lb.main.arn
	port = "443"
	protocol = "HTTPS"
	ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"
	certificate_arn = data.aws_acm_certificate.main.arn
	
	default_action {
		type = "forward"
		target_group_arn = aws_lb_target_group.ecs.arn
	}
}

resource "aws_lb_listener" "http" {
	load_balancer_arn = aws_lb.main.arn
	port = "80"
	protocol = "HTTP"
	
	default_action {
		type = "redirect"
		
		redirect {
			port = "443"
			protocol = "HTTPS"
			status_code = "HTTP_301"
		}
	}
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "steakneggs"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "steakneggs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_exec" {
  name = "ecs-exec"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_cluster" "main" {
	name = "steakneggs"
}

resource "aws_ecr_repository" "steakneggs" {
  name = "steakneggs"

  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "steakneggs" {
  repository = aws_ecr_repository.steakneggs.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 3 images"
        selection = {
          tagStatus = "any"
          countType = "imageCountMoreThan"
          countNumber = 3
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "steakneggs" {
  name              = "/ecs/steakneggs"
  retention_in_days = 3
}

resource "aws_ecs_task_definition" "steakneggs" {
  family                   = "steakneggs"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
	task_role_arn      			 = aws_iam_role.ecs_task_role.arn
	
	runtime_platform {
	    operating_system_family = "LINUX"
	    cpu_architecture        = "ARM64"
	  }

  container_definitions = jsonencode([
    {
      name      = "steakneggs"
      image     = "${aws_ecr_repository.steakneggs.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "RAILS_ENV", value = "production" },
        { name = "RAILS_LOG_TO_STDOUT", value = "true" },
        {
          name  = "DATABASE_URL",
          value = "postgresql://steakneggs:${var.db_password}@${aws_db_instance.postgres.endpoint}/steakneggs"
        },
        {
          name  = "REDIS_URL",
					value = "rediss://${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379/0"
				},					
        { name = "API_KEY", value = var.api_key },
        { name = "GQL_KEY", value = var.gql_key },
        { name = "SENTRY_DSN", value = var.sentry_dsn },
				{ name = "SECRET_KEY_BASE", value = var.secret_key_base }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.steakneggs.name
          "awslogs-region"        = "us-west-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "steakneggs-task-definition"
  }
}

resource "aws_ecs_service" "steakneggs" {
  name            = "steakneggs"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.steakneggs.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = [aws_subnet.alb_ecs_public.id, aws_subnet.alb_ecs_public_b.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "steakneggs"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.https]
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "api_key" {
  type      = string
  sensitive = true
}

variable "gql_key" {
  type = string
	sensitive = true
}

variable "sentry_dsn" {
  type = string
	sensitive = true
}

variable "secret_key_base" {
  type      = string
  sensitive = true
}

output "alb_url" {
  value       = aws_lb.main.dns_name
  description = "Load balancer URL for DNS resolution"
}

output "db_endpoint" {
  value = aws_db_instance.postgres.endpoint
}