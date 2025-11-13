import { Injectable } from '@nestjs/common';

@Injectable()
export class AppService {
  getHealth() {
    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      environment: process.env.NODE_ENV || 'development',
    };
  }

  getInfo() {
    return {
      name: 'Order Service API',
      version: '1.0.0',
      description: 'Flink ClickHouse CDC Pipeline - Order Service',
      endpoints: {
        health: '/api/health',
        docs: '/api/docs',
        orders: '/api/orders',
      },
    };
  }
}
