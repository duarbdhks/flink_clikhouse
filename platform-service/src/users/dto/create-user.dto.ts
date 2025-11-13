import { ApiProperty } from '@nestjs/swagger';
import { IsString, IsEmail, IsOptional, Length } from 'class-validator';

export class CreateUserDto {
  @ApiProperty({
    description: '사용자명 (고유)',
    example: 'john_doe',
    minLength: 3,
    maxLength: 50,
  })
  @IsString()
  @Length(3, 50)
  username: string;

  @ApiProperty({
    description: '이메일 (고유)',
    example: 'john.doe@example.com',
  })
  @IsEmail()
  email: string;

  @ApiProperty({
    description: '전화번호',
    example: '010-1234-5678',
    required: false,
  })
  @IsOptional()
  @IsString()
  @Length(0, 20)
  phone?: string;
}
