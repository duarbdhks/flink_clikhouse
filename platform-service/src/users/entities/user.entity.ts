import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  DeleteDateColumn,
  OneToMany,
} from 'typeorm';
import { ApiProperty } from '@nestjs/swagger';
import { Order } from '@/orders/entities/order.entity';

@Entity('users')
export class User {
  @ApiProperty({ description: '사용자 ID', example: 101 })
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @ApiProperty({ description: '사용자명 (고유)', example: 'john_doe' })
  @Column({ type: 'varchar', length: 50, unique: true })
  username: string;

  @ApiProperty({
    description: '이메일 (고유)',
    example: 'john.doe@example.com',
  })
  @Column({ type: 'varchar', length: 100, unique: true })
  email: string;

  @ApiProperty({
    description: '전화번호',
    example: '010-1234-5678',
    required: false,
  })
  @Column({ type: 'varchar', length: 20, nullable: true })
  phone: string;

  @ApiProperty({
    description: '계정 생성 일시',
    example: '2024-12-01T10:00:00.000Z',
  })
  @CreateDateColumn({ type: 'timestamp', name: 'created_at' })
  createdAt: Date;

  @ApiProperty({
    description: '마지막 수정 일시',
    example: '2024-12-01T10:00:00.000Z',
  })
  @UpdateDateColumn({ type: 'timestamp', name: 'updated_at' })
  updatedAt: Date;

  @ApiProperty({
    description: 'Soft Delete 일시 (NULL=활성)',
    example: null,
    required: false,
  })
  @DeleteDateColumn({ type: 'timestamp', name: 'deleted_at', nullable: true })
  deletedAt: Date | null;

  @ApiProperty({
    description: '사용자의 주문 목록',
    type: () => Order,
    isArray: true,
  })
  @OneToMany(() => Order, (order) => order.user)
  orders: Order[];
}
