[
  {
    "name": "${container_name}",
    "image": "${docker_image}",
    "cpu": ${cpu},
    "memory": ${memory},
    "essential": true,
    "environment": [
      { "name": "DATABASE_URL"                , "value": "${DATABASE_URL}" }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${awslogs_group}",
        "awslogs-region": "${aws_region}",
        "awslogs-stream-prefix": "iri"
      }
    },
    "command": [],
    "entryPoint": [],
    "mountPoints": [],
    "volumesFrom": []
  }
]
