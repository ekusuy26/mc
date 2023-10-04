include .env

up:
	docker-compose up -d
build_upd:
	docker-compose up -d --build
build_up:
	docker-compose up --build
backend:
	docker-compose exec backend bash
db:
	docker-compose exec db bash
connect_db:
	docker-compose exec db mysql -u $(DB_USER) -p$(DB_PASS)
