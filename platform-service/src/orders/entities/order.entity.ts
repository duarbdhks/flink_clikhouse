import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  DeleteDateColumn,
  OneToMany,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { ApiProperty } from '@nestjs/swagger';
import { OrderItem } from './order-item.entity';
import { User } from '@/users/entities/user.entity';

export enum OrderStatus {
  PENDING = 'PENDING',
  PROCESSING = 'PROCESSING',
  COMPLETED = 'COMPLETED',
  CANCELLED = 'CANCELLED',
}

@Entity('orders')
export class Order {
  @ApiProperty({ description: '주문 ID', example: 1 })
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @ApiProperty({ description: '사용자 ID', example: 101 })
  @Column({ type: 'bigint', name: 'user_id' })
  userId: number;

  @ApiProperty({
    description: '주문 상태',
    enum: OrderStatus,
    example: OrderStatus.PENDING,
  })
  @Column({
    type: 'varchar',
    length: 20,
    default: OrderStatus.PENDING,
  })
  status: OrderStatus;

  @ApiProperty({ description: '총 주문 금액', example: 1799000.0 })
  @Column({
    type: 'decimal',
    precision: 10,
    scale: 2,
    default: 0.0,
    name: 'total_amount',
  })
  totalAmount: number;

  @ApiProperty({ description: '주문 생성 일시', example: '2025-01-10T09:15:30.000Z' })
  @CreateDateColumn({ type: 'timestamp', name: 'order_date' })
  orderDate: Date;

  @ApiProperty({ description: '마지막 수정 일시', example: '2025-01-10T09:15:30.000Z' })
  @UpdateDateColumn({ type: 'timestamp', name: 'updated_at' })
  updatedAt: Date;

  @ApiProperty({
    description: 'Soft Delete 일시 (NULL=활성)',
    example: null,
    required: false,
  })
  @DeleteDateColumn({ type: 'timestamp', name: 'deleted_at', nullable: true })
  deletedAt: Date | null;

  @ApiProperty({ description: '주문 항목 목록', type: () => [OrderItem] })
  @OneToMany(() => OrderItem, (orderItem) => orderItem.order, {
    cascade: true,
    eager: true,
  })
  items: OrderItem[];

  @ApiProperty({ description: '주문한 사용자', type: () => User })
  @ManyToOne(() => User, (user) => user.orders)
  @JoinColumn({ name: 'user_id' })
  user: User;
}
