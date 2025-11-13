import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
} from 'typeorm';
import { ApiProperty } from '@nestjs/swagger';
import { Order } from './order.entity';

@Entity('order_items')
export class OrderItem {
  @ApiProperty({ description: '주문 항목 ID', example: 1 })
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @ApiProperty({ description: '주문 ID', example: 1 })
  @Column({ type: 'bigint', name: 'order_id' })
  orderId: number;

  @ApiProperty({ description: '상품 ID', example: 1001 })
  @Column({ type: 'bigint', name: 'product_id' })
  productId: number;

  @ApiProperty({ description: '상품명', example: '삼성 갤럭시 S24' })
  @Column({ type: 'varchar', length: 255, name: 'product_name' })
  productName: string;

  @ApiProperty({ description: '수량', example: 1 })
  @Column({ type: 'int', default: 1 })
  quantity: number;

  @ApiProperty({ description: '단가', example: 1299000.0 })
  @Column({ type: 'decimal', precision: 10, scale: 2 })
  price: number;

  @ApiProperty({ description: '소계 (수량 * 단가)', example: 1299000.0 })
  @Column({ type: 'decimal', precision: 10, scale: 2 })
  subtotal: number;

  @ApiProperty({ description: '생성 일시', example: '2025-01-10T09:15:30.000Z' })
  @CreateDateColumn({ type: 'timestamp', name: 'created_at' })
  createdAt: Date;

  @ManyToOne(() => Order, (order) => order.items, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'order_id' })
  order: Order;
}
