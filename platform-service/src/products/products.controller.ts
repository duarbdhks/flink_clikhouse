import {
  Controller,
  Get,
  Post,
  Put,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  ParseIntPipe,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiParam,
  ApiQuery,
} from '@nestjs/swagger';
import { ProductsService } from './products.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';
import { Product } from './entities/product.entity';

@ApiTags('Products')
@Controller('api/products')
export class ProductsController {
  constructor(private readonly productsService: ProductsService) {}

  @Get()
  @ApiOperation({ summary: '전체 상품 조회 (페이지네이션 및 카테고리 필터)' })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 10 })
  @ApiQuery({ name: 'category', required: false, example: '전자제품' })
  @ApiResponse({
    status: 200,
    description: '상품 목록 조회 성공',
    type: [Product],
  })
  async findAll(
    @Query('page', ParseIntPipe) page: number = 1,
    @Query('limit', ParseIntPipe) limit: number = 10,
    @Query('category') category?: string,
  ): Promise<Product[]> {
    return this.productsService.findAll(page, limit, category);
  }

  @Get('stats/category')
  @ApiOperation({ summary: '카테고리별 상품 수 통계' })
  @ApiResponse({
    status: 200,
    description: '카테고리별 상품 수 조회 성공',
  })
  async countByCategory(): Promise<{ category: string; count: number }[]> {
    return this.productsService.countByCategory();
  }

  @Get(':id')
  @ApiOperation({ summary: '특정 상품 조회' })
  @ApiParam({ name: 'id', description: '상품 ID', example: 1001 })
  @ApiResponse({
    status: 200,
    description: '상품 조회 성공',
    type: Product,
  })
  @ApiResponse({ status: 404, description: '상품을 찾을 수 없음' })
  async findOne(@Param('id', ParseIntPipe) id: number): Promise<Product> {
    return this.productsService.findOne(id);
  }

  @Post()
  @ApiOperation({ summary: '상품 생성' })
  @ApiResponse({
    status: 201,
    description: '상품 생성 성공',
    type: Product,
  })
  async create(@Body() createProductDto: CreateProductDto): Promise<Product> {
    return this.productsService.create(createProductDto);
  }

  @Put(':id')
  @ApiOperation({ summary: '상품 수정' })
  @ApiParam({ name: 'id', description: '상품 ID', example: 1001 })
  @ApiResponse({
    status: 200,
    description: '상품 수정 성공',
    type: Product,
  })
  @ApiResponse({ status: 404, description: '상품을 찾을 수 없음' })
  async update(
    @Param('id', ParseIntPipe) id: number,
    @Body() updateProductDto: UpdateProductDto,
  ): Promise<Product> {
    return this.productsService.update(id, updateProductDto);
  }

  @Patch(':id/stock')
  @ApiOperation({ summary: '상품 재고 조정 (증가/감소)' })
  @ApiParam({ name: 'id', description: '상품 ID', example: 1001 })
  @ApiResponse({
    status: 200,
    description: '재고 조정 성공',
    type: Product,
  })
  @ApiResponse({ status: 404, description: '상품을 찾을 수 없음' })
  @ApiResponse({
    status: 400,
    description: '재고가 음수가 될 수 없음',
  })
  async adjustStock(
    @Param('id', ParseIntPipe) id: number,
    @Body('quantity', ParseIntPipe) quantity: number,
  ): Promise<Product> {
    return this.productsService.adjustStock(id, quantity);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: '상품 삭제' })
  @ApiParam({ name: 'id', description: '상품 ID', example: 1001 })
  @ApiResponse({ status: 204, description: '상품 삭제 성공' })
  @ApiResponse({ status: 404, description: '상품을 찾을 수 없음' })
  async remove(@Param('id', ParseIntPipe) id: number): Promise<void> {
    return this.productsService.remove(id);
  }
}
