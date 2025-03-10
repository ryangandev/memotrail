import { prisma } from '@/lib/prisma';

export const createUser = async (userId: string, email: string) => {
  return await prisma.user.create({
    data: {
      id: userId,
      email,
    },
  });
};
