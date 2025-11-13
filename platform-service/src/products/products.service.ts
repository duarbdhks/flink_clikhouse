import {
  Injectable,
  NotFoundException,
  ConflictException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Product } from './entities/product.entity';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';

@Injectable()
export class ProductsService {
  constructor(
    @InjectRepository(Product)
    private readonly productRepository: Repository<Product>,
  ) {}

  /**
   * 모든 상품 조회 (페이지네이션 및 카테고리 필터)
   */
  async findAll(
    page: number = 1,
    limit: number = 10,
    category?: string,
  ): Promise<Product[]> {
    const skip = (page - 1) * limit;
    const queryBuilder = this.productRepository
      .createQueryBuilder('product')
      .skip(skip)
      .take(limit)
      .orderBy('product.id', 'DESC');

    if (category) {
      queryBuilder.where('product.category = :category', { category });
    }

    return queryBuilder.getMany();
  }

  /**
   * 특정 상품 조회
   */
  async findOne(id: number): Promise<Product> {
    const product = await this.productRepository.findOne({
      where: { id },
    });

    if (!product) {
      throw new NotFoundException(`Product with ID ${id} not found`);
    }

    return product;
  }

  /**
   * 상품 생성
   */
  async create(createProductDto: CreateProductDto): Promise<Product> {
    const product = this.productRepository.create(createProductDto);
    return this.productRepository.save(product);
  }

  /**
   * 상품 수정
   */
  async update(
    id: number,
    updateProductDto: UpdateProductDto,
  ): Promise<Product> {
    const product = await this.findOne(id);

    Object.assign(product, updateProductDto);
    return this.productRepository.save(product);
  }

  /**
   * 상품 삭제
   */
  async remove(id: number): Promise<void> {
    const product = await this.findOne(id);

    // TODO: 주문 항목이 있는 상품은 삭제 불가 (애플리케이션 레벨 참조 무결성)
    // OrderItem 엔티티와 연결 후 체크 로직 추가 필요

    await this.productRepository.remove(product);
  }

  /**
   * 재고 조정 (증가/감소)
   */
  async adjustStock(id: number, quantity: number): Promise<Product> {
    const product = await this.findOne(id);

    const newStock = product.stock + quantity;

    if (newStock < 0) {
      throw new BadRequestException(
        `Cannot adjust stock. Resulting stock (${newStock}) cannot be negative.`,
      );
    }

    product.stock = newStock;
    return this.productRepository.save(product);
  }

  /**
   * 카테고리별 상품 수 조회
   */
  async countByCategory(): Promise<{ category: string; count: number }[]> {
    const results = await this.productRepository
      .createQueryBuilder('product')
      .select('product.category', 'category')
      .addSelect('COUNT(product.id)', 'count')
      .groupBy('product.category')
      .getRawMany();

    return results.map((r) => ({
      category: r.category || 'Uncategorized',
      count: parseInt(r.count, 10),
    }));
  }
}
