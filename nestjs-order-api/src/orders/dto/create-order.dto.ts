import { ApiProperty } from '@nestjs/swagger';
import {
  IsNotEmpty,
  IsNumber,
  IsPositive,
  IsArray,
  ValidateNested,
  ArrayMinSize,
} from 'class-validator';
import { Type } from 'class-transformer';
import { CreateOrderItemDto } from './create-order-item.dto';

export class CreateOrderDto {
  @ApiProperty({ description: '사용자 ID', example: 101 })
  @IsNotEmpty()
  @IsNumber()
  @IsPositive()
  userId: number;

  @ApiProperty({
    description: '주문 항목 목록',
    type: [CreateOrderItemDto],
    example: [
      {
        productId: 1001,
        productName: '삼성 갤럭시 S24',
        quantity: 1,
        price: 1299000.0,
      },
      {
        productId: 1002,
        productName: '갤럭시 버즈 프로',
        quantity: 1,
        price: 250000.0,
      },
    ],
  })
  @IsArray()
  @ArrayMinSize(1, { message: '최소 1개 이상의 상품이 필요합니다' })
  @ValidateNested({ each: true })
  @Type(() => CreateOrderItemDto)
  items: CreateOrderItemDto[];
}
