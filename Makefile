include .env

up:
	docker-compose up -d
build_upd:
	docker-compose up -d --build
build_up:
	docker-compose up --build
down:
	docker-compose down
frontend:
	docker-compose exec frontend sh
backend:
	docker-compose exec backend bash
nginx:
	docker-compose exec nginx bash
db:
	docker-compose exec db bash
connect_db:
	docker-compose exec db mysql -u $(DB_USER) -p$(DB_PASS)
install_nextjs:
	docker-compose exec frontend yarn create next-app . --typescript
