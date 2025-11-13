import { Controller, Get } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { AppService } from './app.service';

@ApiTags('health')
@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get('health')
  @ApiOperation({ summary: 'Health Check', description: 'API 서버 상태 확인' })
  @ApiResponse({ status: 200, description: '서버 정상 동작' })
  getHealth() {
    return this.appService.getHealth();
  }

  @Get()
  @ApiOperation({ summary: 'API Info', description: 'API 정보 조회' })
  @ApiResponse({ status: 200, description: 'API 정보 반환' })
  getInfo() {
    return this.appService.getInfo();
  }
}
