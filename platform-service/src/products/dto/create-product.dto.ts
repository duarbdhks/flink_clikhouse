import { ApiProperty } from '@nestjs/swagger';
import {
  IsString,
  IsNumber,
  IsOptional,
  IsInt,
  Min,
  Length,
} from 'class-validator';

export class CreateProductDto {
  @ApiProperty({
    description: '상품명',
    example: '삼성 갤럭시 S24',
    minLength: 1,
    maxLength: 255,
  })
  @IsString()
  @Length(1, 255)
  name: string;

  @ApiProperty({
    description: '카테고리',
    example: '전자제품',
    maxLength: 50,
    required: false,
  })
  @IsOptional()
  @IsString()
  @Length(0, 50)
  category?: string;

  @ApiProperty({
    description: '판매 가격',
    example: 1299000.0,
  })
  @IsNumber()
  @Min(0)
  price: number;

  @ApiProperty({
    description: '재고 수량',
    example: 50,
    default: 0,
  })
  @IsInt()
  @Min(0)
  stock: number;

  @ApiProperty({
    description: '상품 설명',
    example: '최신 삼성 플래그십 스마트폰',
    required: false,
  })
  @IsOptional()
  @IsString()
  description?: string;
}
