FROM node:18.18.0-alpine

RUN mkdir -p /root/src

WORKDIR /root/src

COPY paclage.json ./

RUN yarn install

# EXPOSE 3000

CMD ["yarn","start"]
