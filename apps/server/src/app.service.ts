import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class AppService {
  constructor(private readonly configService: ConfigService) {}
  getHello(): object {
    const dashboardEnabled =
      this.configService.get<{ enabled?: boolean }>('dashboard')?.enabled ??
      true;
    return {
      service: 'wewe-rss',
      status: 'ok',
      mode: dashboardEnabled ? 'dashboard' : 'headless',
    };
  }
}
