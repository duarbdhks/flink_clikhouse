import { ApiProperty } from '@nestjs/swagger';
import { IsEnum, IsOptional } from 'class-validator';
import { OrderStatus } from '../entities/order.entity';

export class UpdateOrderDto {
  @ApiProperty({
    description: '주문 상태',
    enum: OrderStatus,
    example: OrderStatus.PROCESSING,
    required: false,
  })
  @IsOptional()
  @IsEnum(OrderStatus, { message: '유효한 주문 상태를 입력해주세요' })
  status?: OrderStatus;
}
