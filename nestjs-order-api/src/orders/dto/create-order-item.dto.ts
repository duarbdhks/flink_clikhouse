import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsNumber, IsString, IsPositive, Min } from 'class-validator';

export class CreateOrderItemDto {
  @ApiProperty({ description: '상품 ID', example: 1001 })
  @IsNotEmpty()
  @IsNumber()
  @IsPositive()
  productId: number;

  @ApiProperty({ description: '상품명', example: '삼성 갤럭시 S24' })
  @IsNotEmpty()
  @IsString()
  productName: string;

  @ApiProperty({ description: '수량', example: 1, minimum: 1 })
  @IsNotEmpty()
  @IsNumber()
  @Min(1)
  quantity: number;

  @ApiProperty({ description: '단가', example: 1299000.0 })
  @IsNotEmpty()
  @IsNumber()
  @IsPositive()
  price: number;
}
