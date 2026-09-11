import { TrpcService } from './trpc.service';
import { statusMap } from '../constants';

describe('WeRead account balancing', () => {
  let service: TrpcService;
  let accounts: { id: string; token: string; status: number }[];
  let prisma: any;
  let onError: (error: any) => Promise<never>;
  const choose = () => (service as any).getAvailableAccount();
  const failure = (id: string | undefined, message: string) => ({
    config: { headers: { xid: id } },
    response: { data: { message } },
  });

  afterEach(() => jest.restoreAllMocks());

  beforeEach(() => {
    jest.spyOn(Math, 'random').mockReturnValue(0);
    accounts = ['a', 'b', 'c'].map((id) => ({ id, token: 'test', status: 1 }));
    prisma = {
      account: {
        findMany: jest.fn(async ({ where }) =>
          accounts
            .filter(
              (account) =>
                account.status === where.status &&
                !where.NOT.id.in.includes(account.id),
            )
            .sort((a, b) => a.id.localeCompare(b.id)),
        ),
        update: jest.fn(async ({ where, data }) => {
          Object.assign(
            accounts.find((account) => account.id === where.id)!,
            data,
          );
        }),
      },
    };
    service = new TrpcService(prisma, {
      get: () => ({ url: 'https://example.test', updateDelayTime: 60 }),
    } as any);
    onError = (service.request.interceptors.response as any).handlers[0]
      .rejected;
  });

  it('randomly selects each eligible account and allows consecutive repeats', async () => {
    const random = Math.random as jest.Mock;
    random
      .mockReturnValueOnce(0.99)
      .mockReturnValueOnce(0.99)
      .mockReturnValueOnce(0)
      .mockReturnValueOnce(0.5);
    expect(
      (await Promise.all(Array.from({ length: 4 }, choose))).map((a) => a.id),
    ).toEqual(['c', 'c', 'a', 'b']);
  });

  it('includes accounts beyond the former ten account limit', async () => {
    accounts = Array.from({ length: 12 }, (_, i) => ({
      id: String(i).padStart(2, '0'),
      token: 'test',
      status: 1,
    }));
    (Math.random as jest.Mock).mockReturnValue(0.999);
    expect((await choose()).id).toBe('11');
    expect(prisma.account.findMany.mock.calls[0][0].take).toBeUndefined();
  });

  it('handles disabling, deletion, and newly enabled accounts', async () => {
    expect((await choose()).id).toBe('a');
    accounts[1].status = 2;
    (Math.random as jest.Mock).mockReturnValue(0.999);
    expect((await choose()).id).toBe('c');
    accounts = accounts.filter((a) => a.id !== 'c');
    accounts[1].status = 1;
    (Math.random as jest.Mock)
      .mockReturnValueOnce(0)
      .mockReturnValueOnce(0.999);
    expect((await choose()).id).toBe('a');
    expect((await choose()).id).toBe('b');
  });

  it('supports a single account and fails explicitly when none are enabled', async () => {
    accounts = accounts.slice(0, 1);
    expect((await choose()).id).toBe('a');
    expect((await choose()).id).toBe('a');
    accounts[0].status = 2;
    await expect(choose()).rejects.toThrow('暂无可用读书账号');
  });

  it('blocks a rate-limited account immediately and recovers on manual enable or next day', async () => {
    const date = jest
      .spyOn(service as any, 'getTodayDate')
      .mockReturnValue('2026-09-10');
    for (let i = 0; i < 2; i++)
      await expect(
        onError(failure('a', 'WeReadError429')),
      ).rejects.toBeDefined();
    expect(service.getBlockedAccountIds()).toEqual(['a']);
    expect((await choose()).id).toBe('b');
    service.removeBlockedAccount('a');
    expect(service.getBlockedAccountIds()).toEqual([]);
    await expect(onError(failure('a', 'WeReadError429'))).rejects.toBeDefined();
    date.mockReturnValue('2026-09-11');
    expect(service.getBlockedAccountIds()).toEqual([]);
  });

  it('marks expired credentials invalid and does not block other errors or login polling', async () => {
    await expect(onError(failure('a', 'WeReadError401'))).rejects.toBeDefined();
    expect(accounts[0].status).toBe(statusMap.INVALID);
    await expect(onError(failure('b', 'WeReadError429'))).rejects.toBeDefined();
    await expect(onError(failure('c', 'network error'))).rejects.toBeDefined();
    await expect(
      onError(failure(undefined, 'WeReadError401')),
    ).rejects.toBeDefined();
    await expect(onError({ message: 'network error' })).rejects.toBeDefined();
    expect(service.getBlockedAccountIds()).toEqual(['b']);
    expect((await choose()).id).toBe('c');
  });

  it('rechecks exclusions after an in-flight database query', async () => {
    let resolve: any;
    prisma.account.findMany.mockImplementationOnce(
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    );
    const pending = choose();
    await expect(onError(failure('a', 'WeReadError429'))).rejects.toBeDefined();
    resolve(accounts);
    expect((await pending).id).toBe('b');
  });

  it('randomly selects for article reads, retries, and MP info requests', async () => {
    (Math.random as jest.Mock)
      .mockReturnValueOnce(0)
      .mockReturnValueOnce(0.5)
      .mockReturnValueOnce(0.99);
    const ids: string[] = [];
    jest
      .spyOn(service.request, 'get')
      .mockImplementation(async (_url, config) => {
        ids.push(config!.headers!.xid as string);
        if (ids.length === 1) throw new Error('temporary network error');
        return { data: [] };
      });
    jest
      .spyOn(service.request, 'post')
      .mockImplementation(async (_url, _body, config) => {
        ids.push(config!.headers!.xid as string);
        return { data: [] };
      });
    await service.getMpArticles('mp');
    await service.getMpInfo('https://mp.weixin.qq.com/s/test');
    expect(ids).toEqual(['a', 'b', 'c']);
  });
});
