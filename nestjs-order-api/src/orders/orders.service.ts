import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { CreateOrderDto } from './dto/create-order.dto';
import { QueryOrderDto } from './dto/query-order.dto';
import { UpdateOrderDto } from './dto/update-order.dto';
import { OrderItem } from './entities/order-item.entity';
import { Order, OrderStatus } from './entities/order.entity';

@Injectable()
export class OrdersService {
  constructor(
    @InjectRepository(Order)
    private readonly orderRepository: Repository<Order>,
    @InjectRepository(OrderItem)
    private readonly orderItemRepository: Repository<OrderItem>,
  ) {}

  async create(createOrderDto: CreateOrderDto): Promise<Order> {
    const { userId, items } = createOrderDto;

    // 주문 항목별 소계 계산
    const orderItems = items.map((item) => {
      const orderItem = new OrderItem();
      orderItem.productId = item.productId;
      orderItem.productName = item.productName;
      orderItem.quantity = item.quantity;
      orderItem.price = item.price;
      orderItem.subtotal = item.quantity * item.price;
      return orderItem;
    });

    // 총 주문 금액 계산
    const totalAmount = orderItems.reduce(
      (sum, item) => sum + Number(item.subtotal),
      0,
    );

    // 주문 생성
    const order = this.orderRepository.create({
      userId,
      status: OrderStatus.PENDING,
      totalAmount,
      items: orderItems,
    });

    return await this.orderRepository.save(order);
  }

  async findAll(queryDto: QueryOrderDto): Promise<{
    data: Order[];
    total: number;
    page: number;
    limit: number;
    totalPages: number;
  }> {
    const { status, userId, page = 1, limit = 10 } = queryDto;

    const queryBuilder = this.orderRepository
      .createQueryBuilder('order')
      .leftJoinAndSelect('order.items', 'items')
      .orderBy('order.orderDate', 'DESC');

    // 필터 적용
    if (status) {
      queryBuilder.andWhere('order.status = :status', { status });
    }
    if (userId) {
      queryBuilder.andWhere('order.userId = :userId', { userId });
    }

    // 페이지네이션
    const skip = (page - 1) * limit;
    queryBuilder.skip(skip).take(limit);

    const [data, total] = await queryBuilder.getManyAndCount();

    return {
      data,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  async findOne(id: number): Promise<Order> {
    const order = await this.orderRepository.findOne({
      where: { id },
      relations: ['items'],
    });

    if (!order) {
      throw new NotFoundException(`주문 ID ${id}를 찾을 수 없습니다`);
    }

    return order;
  }

  async update(id: number, updateOrderDto: UpdateOrderDto): Promise<Order> {
    const order = await this.findOne(id);

    // 상태 변경 검증
    if (updateOrderDto.status) {
      this.validateStatusTransition(order.status, updateOrderDto.status);
      order.status = updateOrderDto.status;
    }

    return await this.orderRepository.save(order);
  }

  async remove(id: number): Promise<void> {
    const order = await this.findOne(id);

    // 취소 가능 상태 검증
    if (order.status === OrderStatus.COMPLETED) {
      throw new BadRequestException('완료된 주문은 취소할 수 없습니다');
    }

    if (order.status === OrderStatus.CANCELLED) {
      throw new BadRequestException('이미 취소된 주문입니다');
    }

    // 주문 취소 처리
    order.status = OrderStatus.CANCELLED;
    await this.orderRepository.save(order);
  }

  async getStatistics(): Promise<{
    totalOrders: number;
    totalRevenue: number;
    statusBreakdown: { status: string; count: number; revenue: number }[];
  }> {
    const orders = await this.orderRepository.find();

    const totalOrders = orders.length;
    const totalRevenue = orders.reduce(
      (sum, order) => sum + Number(order.totalAmount),
      0,
    );

    const statusMap = new Map<
      string,
      { count: number; revenue: number }
    >();

    orders.forEach((order) => {
      const current = statusMap.get(order.status) || { count: 0, revenue: 0 };
      statusMap.set(order.status, {
        count: current.count + 1,
        revenue: current.revenue + Number(order.totalAmount),
      });
    });

    const statusBreakdown = Array.from(statusMap.entries()).map(
      ([status, data]) => ({
        status,
        ...data,
      }),
    );

    return {
      totalOrders,
      totalRevenue,
      statusBreakdown,
    };
  }

  private validateStatusTransition(
    currentStatus: OrderStatus,
    newStatus: OrderStatus,
  ): void {
    const validTransitions: Record<OrderStatus, OrderStatus[]> = {
      [OrderStatus.PENDING]: [OrderStatus.PROCESSING, OrderStatus.CANCELLED],
      [OrderStatus.PROCESSING]: [OrderStatus.COMPLETED, OrderStatus.CANCELLED],
      [OrderStatus.COMPLETED]: [],
      [OrderStatus.CANCELLED]: [],
    };

    const allowedTransitions = validTransitions[currentStatus];

    if (!allowedTransitions.includes(newStatus)) {
      throw new BadRequestException(
        `${currentStatus}에서 ${newStatus}로 상태 변경이 불가능합니다`,
      );
    }
  }
}
