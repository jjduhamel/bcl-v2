import { ethers, providers } from 'ethers';
const { JsonRpcProvider } = providers;

export default function() {
  const ensProvider = new JsonRpcProvider('https://mainnet.infura.io/v3/2185ad08ea904e85b06c383c4cd6b902');

  function isAddress(addr) {
    return addr.match(/0x[a-fA-F0-9]{40}/) !== null;
  }

  function isENSDomain(domain) {
    return domain.match(/.+\.eth/) !== null;
  }

  function truncAddress(addr, padstart, padstop) {
    if (!addr) return '???';
    if (!padstart) padstart = 3;
    if (!padstop) padstop = padstart;
    if (addr.match(/0x[a-fA-F0-9]{40}/)) {
      return addr.substring(0,padstart+2)+'..'+addr.substring(42-padstop);
    } else {
      throw new Error('Invalid address', addr);
    }
  }

  async function lookupENS(domain) {
    return ensProvider.resolveName(domain);
  }

  return {
    isAddress,
    isENSDomain,
    truncAddress,
    lookupENS
  };
}
