import {
  Controller,
  Get,
  Post,
  Body,
  Patch,
  Param,
  Delete,
  Query,
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
import { OrdersService } from './orders.service';
import { CreateOrderDto } from './dto/create-order.dto';
import { UpdateOrderDto } from './dto/update-order.dto';
import { QueryOrderDto } from './dto/query-order.dto';
import { Order } from './entities/order.entity';

@ApiTags('orders')
@Controller('orders')
export class OrdersController {
  constructor(private readonly ordersService: OrdersService) {}

  @Post()
  @ApiOperation({
    summary: '주문 생성',
    description: '새로운 주문을 생성합니다. 주문 항목은 최소 1개 이상 필요합니다.',
  })
  @ApiResponse({
    status: 201,
    description: '주문이 성공적으로 생성되었습니다',
    type: Order,
  })
  @ApiResponse({ status: 400, description: '잘못된 요청 데이터' })
  async create(@Body() createOrderDto: CreateOrderDto): Promise<Order> {
    return await this.ordersService.create(createOrderDto);
  }

  @Get()
  @ApiOperation({
    summary: '주문 목록 조회',
    description: '주문 목록을 페이지네이션과 필터링을 적용하여 조회합니다.',
  })
  @ApiResponse({
    status: 200,
    description: '주문 목록 조회 성공',
  })
  async findAll(@Query() queryDto: QueryOrderDto) {
    return await this.ordersService.findAll(queryDto);
  }

  @Get('statistics')
  @ApiOperation({
    summary: '주문 통계',
    description: '전체 주문 통계 정보를 조회합니다 (총 주문 건수, 매출, 상태별 집계)',
  })
  @ApiResponse({
    status: 200,
    description: '통계 조회 성공',
  })
  async getStatistics() {
    return await this.ordersService.getStatistics();
  }

  @Get(':id')
  @ApiOperation({
    summary: '주문 상세 조회',
    description: '특정 주문의 상세 정보를 조회합니다. 주문 항목 정보도 포함됩니다.',
  })
  @ApiParam({ name: 'id', description: '주문 ID', example: 1 })
  @ApiResponse({
    status: 200,
    description: '주문 상세 정보 조회 성공',
    type: Order,
  })
  @ApiResponse({ status: 404, description: '주문을 찾을 수 없습니다' })
  async findOne(@Param('id') id: string): Promise<Order> {
    return await this.ordersService.findOne(+id);
  }

  @Patch(':id')
  @ApiOperation({
    summary: '주문 상태 업데이트',
    description: '주문 상태를 업데이트합니다. 유효한 상태 전환만 가능합니다.',
  })
  @ApiParam({ name: 'id', description: '주문 ID', example: 1 })
  @ApiResponse({
    status: 200,
    description: '주문 상태 업데이트 성공',
    type: Order,
  })
  @ApiResponse({ status: 400, description: '잘못된 상태 전환' })
  @ApiResponse({ status: 404, description: '주문을 찾을 수 없습니다' })
  async update(
    @Param('id') id: string,
    @Body() updateOrderDto: UpdateOrderDto,
  ): Promise<Order> {
    return await this.ordersService.update(+id, updateOrderDto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: '주문 취소',
    description: '주문을 취소합니다. 완료된 주문은 취소할 수 없습니다.',
  })
  @ApiParam({ name: 'id', description: '주문 ID', example: 1 })
  @ApiResponse({ status: 204, description: '주문이 취소되었습니다' })
  @ApiResponse({
    status: 400,
    description: '취소할 수 없는 주문 (완료/이미 취소됨)',
  })
  @ApiResponse({ status: 404, description: '주문을 찾을 수 없습니다' })
  async remove(@Param('id') id: string): Promise<void> {
    await this.ordersService.remove(+id);
  }
}
