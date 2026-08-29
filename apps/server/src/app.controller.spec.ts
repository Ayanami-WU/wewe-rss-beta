import { AppController } from './app.controller';
import { AppService } from './app.service';
import { NotFoundException } from '@nestjs/common';

describe('AppController', () => {
  const createController = (dashboardEnabled: boolean) => {
    const configService = {
      get: jest.fn((key: string) => {
        if (key === 'dashboard') {
          return { enabled: dashboardEnabled };
        }
        if (key === 'feed') {
          return { originUrl: undefined };
        }
        if (key === 'auth') {
          return { code: undefined };
        }
        return undefined;
      }),
    } as any;
    const appService = new AppService(configService);
    return new AppController(appService, configService);
  };

  describe('root', () => {
    it('returns a headless backend health payload when Dashboard is disabled', () => {
      expect(createController(false).getHello()).toEqual({
        service: 'wewe-rss',
        status: 'ok',
        mode: 'headless',
      });
    });

    it('reports Dashboard mode when the UI is enabled', () => {
      expect(createController(true).getHello()).toEqual({
        service: 'wewe-rss',
        status: 'ok',
        mode: 'dashboard',
      });
    });
  });

  describe('Dashboard', () => {
    it('rejects Dashboard access in headless mode', () => {
      expect(() => createController(false).dashRender()).toThrow(
        NotFoundException,
      );
    });

    it('keeps Dashboard render data available when enabled', () => {
      const controller = createController(true);
      expect(controller.dashRender()).toEqual({
        weweRssServerOriginUrl: undefined,
        enabledAuthCode: false,
        iconUrl: 'https://r2-assets.111965.xyz/wewe-rss.png',
      });
    });
  });
});
