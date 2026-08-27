const { createApp } = require('./app');

const port = Number(process.env.PORT || 3001);
const app = createApp();

const server = app.listen(port, '0.0.0.0', () => {
  console.log(`[roamline] Listening on http://0.0.0.0:${port}`);
});

function shutdown(signal) {
  console.log(`[roamline] ${signal} received; shutting down`);
  server.close(() => {
    app.locals.db.close();
    process.exit(0);
  });
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
