import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Order } from '@/orders/entities/order.entity';
import { OrderItem } from '@/orders/entities/order-item.entity';
import { User } from '@/users/entities/user.entity';
import { Product } from '@/products/entities/product.entity';

@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (configService: ConfigService) => ({
        type: 'mysql',
        host: configService.get('DB_HOST', 'mysql'),
        port: configService.get<number>('DB_PORT', 3306),
        username: configService.get('DB_USERNAME', 'root'),
        password: configService.get('DB_PASSWORD', 'test123'),
        database: configService.get('DB_DATABASE', 'order_db'),
        entities: [Order, OrderItem, User, Product],
        synchronize: configService.get('TYPEORM_SYNCHRONIZE', 'false') === 'true',
        logging: configService.get('TYPEORM_LOGGING', 'false') === 'true',
        charset: 'utf8mb4',
        timezone: '+09:00',
        extra: {
          connectionLimit: 10,
        },
      }),
      inject: [ConfigService],
    }),
  ],
})
export class DatabaseModule {}
