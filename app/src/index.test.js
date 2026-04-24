const request = require('supertest');
const app = require('./index');

let server;

beforeAll(() => { server = app.listen(0); });
afterAll(() => server.close());

describe('Health endpoint', () => {
  it('returns 200 with healthy status', async () => {
    const res = await request(server).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('healthy');
  });
});

describe('Root endpoint', () => {
  it('returns service name', async () => {
    const res = await request(server).get('/');
    expect(res.statusCode).toBe(200);
    expect(res.body.message).toContain('FinCorp');
  });
});
