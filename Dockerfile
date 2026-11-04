FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY server.js attendance.js attendance-store.js token-route.js ./
EXPOSE 3000
CMD ["node", "server.js"]

