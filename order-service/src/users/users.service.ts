import {
  Injectable,
  NotFoundException,
  ConflictException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from './entities/user.entity';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User)
    private readonly userRepository: Repository<User>,
  ) {}

  /**
   * 모든 사용자 조회 (페이지네이션)
   */
  async findAll(page: number = 1, limit: number = 10): Promise<User[]> {
    const skip = (page - 1) * limit;
    return this.userRepository.find({
      skip,
      take: limit,
      order: { id: 'DESC' },
    });
  }

  /**
   * 특정 사용자 조회
   */
  async findOne(id: number): Promise<User> {
    const user = await this.userRepository.findOne({
      where: { id },
      relations: ['orders'],
    });

    if (!user) {
      throw new NotFoundException(`User with ID ${id} not found`);
    }

    return user;
  }

  /**
   * 사용자명으로 조회
   */
  async findByUsername(username: string): Promise<User> {
    return this.userRepository.findOne({ where: { username } });
  }

  /**
   * 이메일로 조회
   */
  async findByEmail(email: string): Promise<User> {
    return this.userRepository.findOne({ where: { email } });
  }

  /**
   * 사용자 생성
   */
  async create(createUserDto: CreateUserDto): Promise<User> {
    // 중복 체크
    const existingUsername = await this.findByUsername(
      createUserDto.username,
    );
    if (existingUsername) {
      throw new ConflictException(
        `Username '${createUserDto.username}' already exists`,
      );
    }

    const existingEmail = await this.findByEmail(createUserDto.email);
    if (existingEmail) {
      throw new ConflictException(
        `Email '${createUserDto.email}' already exists`,
      );
    }

    const user = this.userRepository.create(createUserDto);
    return this.userRepository.save(user);
  }

  /**
   * 사용자 수정
   */
  async update(id: number, updateUserDto: UpdateUserDto): Promise<User> {
    const user = await this.findOne(id);

    // username 중복 체크 (변경하는 경우)
    if (updateUserDto.username && updateUserDto.username !== user.username) {
      const existingUsername = await this.findByUsername(
        updateUserDto.username,
      );
      if (existingUsername) {
        throw new ConflictException(
          `Username '${updateUserDto.username}' already exists`,
        );
      }
    }

    // email 중복 체크 (변경하는 경우)
    if (updateUserDto.email && updateUserDto.email !== user.email) {
      const existingEmail = await this.findByEmail(updateUserDto.email);
      if (existingEmail) {
        throw new ConflictException(
          `Email '${updateUserDto.email}' already exists`,
        );
      }
    }

    Object.assign(user, updateUserDto);
    return this.userRepository.save(user);
  }

  /**
   * 사용자 삭제
   */
  async remove(id: number): Promise<void> {
    const user = await this.findOne(id);

    // 주문이 있는 사용자는 삭제 불가 (애플리케이션 레벨 참조 무결성)
    if (user.orders && user.orders.length > 0) {
      throw new ConflictException(
        `Cannot delete user with ID ${id} because they have existing orders`,
      );
    }

    await this.userRepository.remove(user);
  }

  /**
   * 사용자별 주문 조회
   */
  async findUserOrders(id: number) {
    const user = await this.userRepository.findOne({
      where: { id },
      relations: ['orders', 'orders.items'],
    });

    if (!user) {
      throw new NotFoundException(`User with ID ${id} not found`);
    }

    return user.orders;
  }
}
