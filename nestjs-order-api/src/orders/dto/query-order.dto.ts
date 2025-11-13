import { ApiProperty } from '@nestjs/swagger';
import { IsOptional, IsEnum, IsNumber, Min } from 'class-validator';
import { Type } from 'class-transformer';
import { OrderStatus } from '../entities/order.entity';

export class QueryOrderDto {
  @ApiProperty({
    description: '주문 상태 필터',
    enum: OrderStatus,
    required: false,
    example: OrderStatus.PENDING,
  })
  @IsOptional()
  @IsEnum(OrderStatus)
  status?: OrderStatus;

  @ApiProperty({
    description: '사용자 ID 필터',
    required: false,
    example: 101,
  })
  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  userId?: number;

  @ApiProperty({
    description: '페이지 번호 (1부터 시작)',
    required: false,
    default: 1,
    minimum: 1,
  })
  @IsOptional()
  @IsNumber()
  @Min(1)
  @Type(() => Number)
  page?: number = 1;

  @ApiProperty({
    description: '페이지당 항목 수',
    required: false,
    default: 10,
    minimum: 1,
  })
  @IsOptional()
  @IsNumber()
  @Min(1)
  @Type(() => Number)
  limit?: number = 10;
}
