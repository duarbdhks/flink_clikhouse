import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Global Validation Pipe
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: {
        enableImplicitConversion: true,
      },
    }),
  );

  // CORS 설정
  app.enableCors({
    origin: process.env.CORS_ORIGIN || '*',
    credentials: true,
  });

  // Global Prefix
  app.setGlobalPrefix('api');

  // Swagger API 문서 설정
  if (process.env.SWAGGER_ENABLED !== 'false') {
    const config = new DocumentBuilder()
      .setTitle('Order Service API')
      .setDescription('Flink ClickHouse CDC Pipeline - Order Service REST API')
      .setVersion('1.0')
      .addTag('orders', '주문 관리 API')
      .addServer('http://localhost:3000', 'Local Development')
      .addServer('http://nestjs-api:3000', 'Docker Environment')
      .build();

    const document = SwaggerModule.createDocument(app, config);
    SwaggerModule.setup('api/docs', app, document, {
      swaggerOptions: {
        persistAuthorization: true,
        tagsSorter: 'alpha',
        operationsSorter: 'alpha',
      },
    });

    console.log(`📚 Swagger API Docs: http://localhost:${process.env.PORT || 3000}/api/docs`);
  }

  const port = process.env.PORT || 3000;
  await app.listen(port);

  console.log(`🚀 Order Service API is running on: http://localhost:${port}/api`);
  console.log(`📊 Health Check: http://localhost:${port}/api/health`);
}

bootstrap();
