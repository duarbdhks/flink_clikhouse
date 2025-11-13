import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';
import { ApiProperty } from '@nestjs/swagger';

@Entity('products')
export class Product {
  @ApiProperty({ description: '상품 ID', example: 1001 })
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @ApiProperty({ description: '상품명', example: '삼성 갤럭시 S24' })
  @Column({ type: 'varchar', length: 255 })
  name: string;

  @ApiProperty({
    description: '카테고리',
    example: '전자제품',
    required: false,
  })
  @Column({ type: 'varchar', length: 50, nullable: true })
  category: string;

  @ApiProperty({ description: '판매 가격', example: 1299000.0 })
  @Column({ type: 'decimal', precision: 10, scale: 2 })
  price: number;

  @ApiProperty({ description: '재고 수량', example: 50 })
  @Column({ type: 'int', default: 0 })
  stock: number;

  @ApiProperty({
    description: '상품 설명',
    example: '최신 삼성 플래그십 스마트폰',
    required: false,
  })
  @Column({ type: 'text', nullable: true })
  description: string;

  @ApiProperty({
    description: '상품 등록 일시',
    example: '2024-11-01T09:00:00.000Z',
  })
  @CreateDateColumn({ type: 'timestamp', name: 'created_at' })
  createdAt: Date;

  @ApiProperty({
    description: '마지막 수정 일시',
    example: '2024-11-01T09:00:00.000Z',
  })
  @UpdateDateColumn({ type: 'timestamp', name: 'updated_at' })
  updatedAt: Date;
}
