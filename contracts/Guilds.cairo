%lang starknet

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_le, assert_lt
from starkware.cairo.common.pow import pow
from starkware.starknet.common.syscalls import (
    call_contract,
    get_caller_address,
    get_contract_address,
)
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_lt,
    uint256_le,
    uint256_eq,
    uint256_add,
    uint256_sub,
    uint256_mul,
    uint256_unsigned_div_rem,
)

from openzeppelin.token.erc20.interfaces.IERC20 import IERC20

from contracts.utils.constants import FALSE, TRUE
from contracts.interfaces.IPriceAggregator import IPriceAggregator
from contracts.interfaces.IShareCertificate import IShareCertificate
from contracts.libraries.Math64x61 import Math64x61_div, Math64x61_mul

#
# Storage
#

@storage_var
func _whitelisted_len() -> (res : felt):
end

@storage_var
func _is_whitelisted_user(whitelisted_user : felt) -> (res : felt):
end

@storage_var
func _tokens_len() -> (res : felt):
end

@storage_var
func _tokens(index : felt) -> (res : felt):
end

@storage_var
func _token_reserves(token : felt) -> (res : Uint256):
end

@storage_var
func _share_certificate() -> (res : felt):
end

#
# Getters
#

@view
func get_is_whitelisted{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    whitelisted_user_address : felt
) -> (value : felt):
    let (value) = _is_whitelisted_user.read(whitelisted_user_address)
    return (value)
end

func _get_tokens{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokens_index : felt, tokens_len : felt, tokens : felt*
):
    if tokens_index == tokens_len:
        return ()
    end

    let (token) = _tokens.read(index=tokens_index)
    assert tokens[tokens_index] = token

    _get_tokens(tokens_index=tokens_index + 1, tokens_len=tokens_len, tokens=tokens)
    return ()
end

@view
func get_tokens{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    tokens_len : felt, tokens : felt*
):
    alloc_locals
    let (tokens) = alloc()
    let (tokens_len) = _tokens_len.read()
    if tokens_len == 0:
        return (tokens_len=tokens_len, tokens=tokens)
    end

    # Recursively add tokens from storage to the tokens array
    _get_tokens(tokens_index=0, tokens_len=tokens_len, tokens=tokens)
    return (tokens_len=tokens_len, tokens=tokens)
end

#
# Guards
#

func only_in_whitelisted{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller_address) = get_caller_address()
    let (is_whitelisted_user) = get_is_whitelisted(caller_address)
    with_attr error_message("Ownable: caller is not whitelisted"):
        assert is_whitelisted_user = TRUE
    end
    return ()
end

#
# Actions
#

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    whitelisted_len : felt,
    whitelisted : felt*,
    tokens_len : felt,
    tokens : felt*,
    token_weights_len : felt,
    token_weights : felt*,
    share_certificate : felt,
):
    _set_whitelisted(
        whitelisted_index=0, whitelisted_len=whitelisted_len, whitelisted=whitelisted, value=TRUE
    )
    _tokens_len.write(value=tokens_len)
    _set_tokens(tokens_index=0, tokens_len=tokens_len, tokens=tokens)
    _share_certificate.write(share_certificate)
    return ()
end

@external
func mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    only_in_whitelisted()
    let (share_certificate) = _share_certificate.read()
    let (caller_address) = get_caller_address()
    let (guild) = get_contract_address()
    IShareCertificate.mint(
        contract_address=share_certificate, guild=guild, owner=caller_address, share=Uint256(0, 7)
    )
    _is_whitelisted_user.write(caller_address, FALSE)
    return ()
end

@external
func add_whitelisted{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    whitelisted_len : felt, whitelisted : felt*
):
    # todo
    # only_in_whitelisted()
    let (current_whitelisted_len) = _whitelisted_len.read()
    _set_whitelisted(
        whitelisted_index=current_whitelisted_len,
        whitelisted_len=current_whitelisted_len + whitelisted_len,
        whitelisted=whitelisted,
        value=TRUE,
    )
    return ()
end

func _add_funds{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokens_index : felt,
    tokens_len : felt,
    tokens : felt*,
    amounts : Uint256*,
    whitelisted_user : felt,
):
    alloc_locals
    if tokens_index == tokens_len:
        return ()
    end

    let (local check_amount) = uint256_lt(Uint256(0, 0), [amounts])
    with_attr error_message("SW Error: Amount must be greater than 0"):
        assert check_amount = TRUE
    end

    let (contract_address) = get_contract_address()
    IERC20.transferFrom(
        contract_address=tokens[tokens_index],
        sender=whitelisted_user,
        recipient=contract_address,
        amount=amounts[tokens_index],
    )

    _add_funds(
        tokens_index=tokens_index + 1,
        tokens_len=tokens_len,
        tokens=tokens,
        amounts=amounts,
        whitelisted_user=whitelisted_user,
    )
    return ()
end

@external
func add_funds{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokens_len : felt, tokens : felt*, amounts_len : felt, amounts : Uint256*
):
    alloc_locals
    only_in_whitelisted()
    with_attr error_message("SW Error: Tokens length does not match amounts"):
        assert tokens_len = amounts_len
    end
    let (caller_address) = get_caller_address()
    let (contract_address) = get_contract_address()

    _add_funds(
        tokens_index=0,
        tokens_len=tokens_len,
        tokens=tokens,
        amounts=amounts,
        whitelisted_user=caller_address,
    )

    _modify_position_add(
        user=caller_address,
        tokens_len=tokens_len,
        tokens=tokens,
        amounts_len=amounts_len,
        amounts=amounts,
    )
    update_reserves()
    return ()
end

@external
func remove_funds{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    amount : Uint256
):
    alloc_locals
    let (local caller_address) = get_caller_address()
    let (contract_address) = get_contract_address()

    let (share_certificate) = _share_certificate.read()
    let (share) = IShareCertificate.get_shares(
        contract_address=share_certificate, owner=caller_address
    )
    let (check_amount) = uint256_le(amount, share)
    with_attr error_message("SW Error: Remove amount cannot be greater than share"):
        assert check_amount = TRUE
    end
    let (amounts_len, amounts) = calculate_tokens_from_share(share=amount)
    distribute_amounts(whitelisted_user=caller_address, amounts_len=amounts_len, amounts=amounts)
    _modify_position_remove(whitelisted_user=caller_address, share=amount)
    update_reserves()
    return ()
end

#
# Storage Helpers
#

func _set_whitelisted{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    whitelisted_index : felt, whitelisted_len : felt, whitelisted : felt*, value : felt
):
    if whitelisted_index == whitelisted_len:
        return ()
    end

    # Write the current iteration to storage
    _is_whitelisted_user.write(whitelisted_user=[whitelisted], value=value)

    # Recursively write the rest
    _set_whitelisted(
        whitelisted_index=whitelisted_index + 1,
        whitelisted_len=whitelisted_len,
        whitelisted=whitelisted + 1,
        value=TRUE,
    )
    return ()
end

func _set_tokens{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokens_index : felt, tokens_len : felt, tokens : felt*
):
    if tokens_index == tokens_len:
        return ()
    end

    # Write the current iteration to storage
    _tokens.write(index=tokens_index, value=[tokens])
    _is_whitelisted_user.write(whitelisted_user=[tokens], value=TRUE)

    # Recursively write the rest
    _set_tokens(tokens_index=tokens_index + 1, tokens_len=tokens_len, tokens=tokens + 1)
    return ()
end

#
# Internals
#

func _modify_position_add{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user : felt, tokens_len : felt, tokens : felt*, amounts_len : felt, amounts : Uint256*
):
    alloc_locals
    let (share_certificate) = _share_certificate.read()
    let (current_total_supply) = IShareCertificate.get_total_shares(
        contract_address=share_certificate
    )
    let (share) = IShareCertificate.get_shares(contract_address=share_certificate, owner=user)
    let (check_supply_zero) = uint256_eq(current_total_supply, Uint256(0, 0))
    let (check_share_zero) = uint256_eq(current_total_supply, Uint256(0, 0))
    let (initial_share : Uint256) = calculate_initial_share(
        tokens_len=tokens_len, tokens=tokens, amounts_len=amounts_len, amounts=amounts
    )
    let (added_share : Uint256) = calculate_share(
        tokens_len=tokens_len, tokens=tokens, amounts_len=amounts_len, amounts=amounts
    )

    let (guild) = get_contract_address()

    if check_supply_zero == TRUE:
        IShareCertificate.mint(
            contract_address=share_certificate, guild=guild, owner=user, share=initial_share
        )
    else:
        if check_share_zero == TRUE:
            IShareCertificate.mint(
                contract_address=share_certificate, guild=guild, owner=user, share=added_share
            )
        else:
            IShareCertificate.increase_shares(
                contract_address=share_certificate, owner=user, amount=added_share
            )
        end
    end
    return ()
end

func _modify_position_remove{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    whitelisted_user : felt, share : Uint256
):
    alloc_locals
    let (share_certificate) = _share_certificate.read()
    let (current_shares) = IShareCertificate.get_shares(
        contract_address=share_certificate, owner=whitelisted_user
    )
    let (check_share) = uint256_le(current_shares, share)
    if check_share == TRUE:
        IShareCertificate.burn(contract_address=share_certificate, owner=whitelisted_user)
    else:
        IShareCertificate.decrease_shares(
            contract_address=share_certificate, owner=whitelisted_user, amount=share
        )
    end
    return ()
end

func update_reserves{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (local tokens_len, tokens) = get_tokens()
    let (balances_len, balances) = get_token_balances()

    _update_reserves(
        tokens_index=0,
        tokens_len=tokens_len,
        tokens=tokens,
        balances_len=balances_len,
        balances=balances,
    )

    return ()
end

func _update_reserves{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokens_index : felt, tokens_len : felt, tokens : felt*, balances_len : felt, balances : Uint256*
):
    if tokens_index == tokens_len:
        return ()
    end

    _token_reserves.write(token=tokens[tokens_index], value=balances[tokens_index])

    _update_reserves(
        tokens_index=tokens_index + 1,
        tokens_len=tokens_len,
        tokens=tokens,
        balances_len=balances_len,
        balances=balances,
    )

    return ()
end

@view
func calculate_tokens_from_share{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    share : Uint256
) -> (amounts_len : felt, amounts : Uint256*):
    alloc_locals
    let (local amounts : Uint256*) = alloc()
    let (tokens_len, tokens) = get_tokens()
    let (reserves_len, reserves) = get_token_reserves()
    if reserves_len == 0:
        return (amounts_len=reserves_len, amounts=amounts)
    end

    # Recursively add amounts from calculation to the amounts array
    _calculate_tokens_from_share(
        tokens_index=0,
        tokens_len=tokens_len,
        tokens=tokens,
        reserves_len=reserves_len,
        reserves=reserves,
        share=share,
        amounts_len=reserves_len,
        amounts=amounts,
    )
    return (amounts_len=reserves_len, amounts=amounts)
end

func _calculate_tokens_from_share{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(
    tokens_index : felt,
    tokens_len : felt,
    tokens : felt*,
    reserves_len : felt,
    reserves : Uint256*,
    share : Uint256,
    amounts_len : felt,
    amounts : Uint256*,
):
    alloc_locals
    if tokens_index == tokens_len:
        return ()
    end

    let (share_certificate) = _share_certificate.read()
    let (total_supply) = IShareCertificate.get_total_shares(contract_address=share_certificate)
    let (token_decimals) = IERC20.decimals(contract_address=tokens[tokens_index])
    let (token_units) = pow(10, token_decimals)

    let unit_reserve_divisor : Uint256 = Uint256(token_units, 0)
    let (get_share_units, _) = uint256_unsigned_div_rem(share, unit_reserve_divisor)
    let (get_reserve_units, _) = uint256_unsigned_div_rem(
        reserves[tokens_index], unit_reserve_divisor
    )
    let (get_total_supply_units, _) = uint256_unsigned_div_rem(total_supply, unit_reserve_divisor)

    let (amount_numerator, _) = uint256_mul(get_share_units, get_reserve_units)
    let (amount_units, _) = uint256_unsigned_div_rem(amount_numerator, get_total_supply_units)
    let (amount, _) = uint256_mul(amount_units, unit_reserve_divisor)
    assert amounts[tokens_index] = amount

    _calculate_tokens_from_share(
        tokens_index=tokens_index + 1,
        tokens_len=tokens_len,
        tokens=tokens,
        reserves_len=reserves_len,
        reserves=reserves,
        share=share,
        amounts_len=amounts_len,
        amounts=amounts,
    )
    return ()
end

@view
func calculate_initial_share{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokens_len : felt, tokens : felt*, amounts_len : felt, amounts : Uint256*
) -> (initial_share : Uint256):
    alloc_locals
    let initial_share : Uint256 = Uint256(1000000000000000000, 0)

    if amounts_len == 0:
        return (initial_share=Uint256(0, 0))
    end

    let (new_share) = _calculate_initial_share(
        tokens_index=0,
        tokens_len=tokens_len,
        tokens=tokens,
        amounts_len=amounts_len,
        amounts=amounts,
        initial_share=initial_share,
    )
    return (initial_share=new_share)
end

func _calculate_initial_share{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokens_index : felt,
    tokens_len : felt,
    tokens : felt*,
    amounts_len : felt,
    amounts : Uint256*,
    initial_share : Uint256,
) -> (new_share : Uint256):
    alloc_locals
    if tokens_index == tokens_len:
        return (new_share=initial_share)
    end
    let (token_decimals) = IERC20.decimals(contract_address=tokens[tokens_index])
    let (token_units) = pow(10, token_decimals)
    let unit_initial_divisor : Uint256 = Uint256(token_units, 0)
    let unit_amount_divisor : Uint256 = Uint256(token_units, 0)
    if tokens_index == 0:
        assert unit_initial_divisor = Uint256(1000000000000000000, 0)
    end
    let (get_initial_units, _) = uint256_unsigned_div_rem(initial_share, unit_initial_divisor)
    let (get_amount_units, _) = uint256_unsigned_div_rem(amounts[tokens_index], unit_amount_divisor)
    let (new_share_units, _) = uint256_mul(get_initial_units, get_amount_units)
    let (new_share, _) = uint256_mul(new_share_units, unit_amount_divisor)

    let (new_share) = _calculate_initial_share(
        tokens_index=tokens_index + 1,
        tokens_len=tokens_len,
        tokens=tokens,
        amounts_len=amounts_len,
        amounts=amounts,
        initial_share=new_share,
    )
    return (new_share=new_share)
end

@view
func calculate_share{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokens_len : felt, tokens : felt*, amounts_len : felt, amounts : Uint256*
) -> (share : Uint256):
    alloc_locals
    let (local share_amounts : Uint256*) = alloc()
    let (reserves_len, reserves) = get_token_reserves()

    if amounts_len == 0:
        return (share=Uint256(0, 0))
    end

    _calculate_share_amounts(
        tokens_index=0,
        tokens_len=tokens_len,
        tokens=tokens,
        amounts_len=amounts_len,
        amounts=amounts,
        reserves_len=reserves_len,
        reserves=reserves,
        share_amounts_len=amounts_len,
        share_amounts=share_amounts,
    )

    let (share) = get_minimum_amount(amounts_len=amounts_len, amounts=share_amounts)

    return (share=share)
end

func _calculate_share_amounts{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokens_index : felt,
    tokens_len : felt,
    tokens : felt*,
    amounts_len : felt,
    amounts : Uint256*,
    reserves_len : felt,
    reserves : Uint256*,
    share_amounts_len : felt,
    share_amounts : Uint256*,
):
    alloc_locals
    if tokens_index == tokens_len:
        return ()
    end

    let (share_certificate) = _share_certificate.read()
    let (total_supply) = IShareCertificate.get_total_shares(contract_address=share_certificate)

    let (token_decimals) = IERC20.decimals(contract_address=tokens[tokens_index])
    let (token_units) = pow(10, token_decimals)
    let unit_amount_divisor : Uint256 = Uint256(token_units, 0)
    let (get_amount_units, _) = uint256_unsigned_div_rem(amounts[tokens_index], unit_amount_divisor)
    let (get_total_supply_units, _) = uint256_unsigned_div_rem(total_supply, unit_amount_divisor)
    let (get_reserves_units, _) = uint256_unsigned_div_rem(
        reserves[tokens_index], unit_amount_divisor
    )

    let (amount_numerator, _) = uint256_mul(get_amount_units, get_total_supply_units)
    let (amount_units, _) = uint256_unsigned_div_rem(amount_numerator, get_reserves_units)
    let (amount, _) = uint256_mul(amount_units, unit_amount_divisor)
    assert share_amounts[tokens_index] = amount

    _calculate_share_amounts(
        tokens_index=tokens_index + 1,
        tokens_len=tokens_len,
        tokens=tokens,
        amounts_len=amounts_len,
        amounts=amounts,
        reserves_len=reserves_len,
        reserves=reserves,
        share_amounts_len=share_amounts_len,
        share_amounts=share_amounts,
    )

    return ()
end

@view
func get_minimum_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    amounts_len : felt, amounts : Uint256*
) -> (minimum : Uint256):
    if amounts_len == 0:
        return (minimum=Uint256(0, 0))
    end

    let (new_minimum) = _get_minimum_amount(
        amounts_index=1, amounts_len=amounts_len, amounts=amounts, minimum=[amounts]
    )
    return (minimum=new_minimum)
end

func _get_minimum_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    amounts_index : felt, amounts_len : felt, amounts : Uint256*, minimum : Uint256
) -> (new_minimum : Uint256):
    alloc_locals
    if amounts_index == amounts_len:
        return (new_minimum=minimum)
    end

    let (check) = uint256_le(minimum, amounts[amounts_index])

    if check == TRUE:
        tempvar new_minimum = minimum
    else:
        tempvar new_minimum = amounts[amounts_index]
    end

    let (new_minimum) = _get_minimum_amount(
        amounts_index=amounts_index + 1,
        amounts_len=amounts_len,
        amounts=amounts,
        minimum=new_minimum,
    )

    return (new_minimum=new_minimum)
end

func get_token_balances{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    balances_len : felt, balances : Uint256*
):
    alloc_locals
    let (tokens_len, tokens) = get_tokens()
    let (local balances : Uint256*) = alloc()

    if tokens_len == 0:
        return (balances_len=tokens_len, balances=balances)
    end

    _get_token_balances(tokens_index=0, tokens_len=tokens_len, tokens=tokens, balances=balances)

    return (balances_len=tokens_len, balances=balances)
end

func _get_token_balances{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokens_index : felt, tokens_len : felt, tokens : felt*, balances : Uint256*
):
    if tokens_index == tokens_len:
        return ()
    end

    let (contract_address) = get_contract_address()
    let (balance) = IERC20.balanceOf(
        contract_address=tokens[tokens_index], account=contract_address
    )
    assert balances[tokens_index] = balance

    _get_token_balances(
        tokens_index=tokens_index + 1, tokens_len=tokens_len, tokens=tokens, balances=balances
    )
    return ()
end

@view
func get_token_reserves{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    reserves_len : felt, reserves : Uint256*
):
    alloc_locals
    let (local tokens_len, tokens) = get_tokens()
    let (local reserves : Uint256*) = alloc()
    if tokens_len == 0:
        return (reserves_len=tokens_len, reserves=reserves)
    end

    # Recursively add reserves from storage to the reserves array
    _get_token_reserves(tokens_index=0, tokens_len=tokens_len, tokens=tokens, reserves=reserves)
    return (reserves_len=tokens_len, reserves=reserves)
end

func _get_token_reserves{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokens_index : felt, tokens_len : felt, tokens : felt*, reserves : Uint256*
):
    if tokens_index == tokens_len:
        return ()
    end

    let (contract_address) = get_contract_address()
    let (reserve) = _token_reserves.read(token=tokens[tokens_index])
    assert reserves[tokens_index] = reserve

    _get_token_reserves(
        tokens_index=tokens_index + 1, tokens_len=tokens_len, tokens=tokens, reserves=reserves
    )
    return ()
end

func distribute_amounts{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    whitelisted_user : felt, amounts_len : felt, amounts : Uint256*
):
    if amounts_len == 0:
        return ()
    end
    let (token_len, tokens) = get_tokens()

    # Recursively send tokens to the whitelisted_user
    _distribute_amounts(
        amounts_index=0,
        amounts_len=amounts_len,
        amounts=amounts,
        whitelisted_user=whitelisted_user,
        tokens=tokens,
    )
    return ()
end

func _distribute_amounts{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    amounts_index : felt,
    amounts_len : felt,
    amounts : Uint256*,
    whitelisted_user : felt,
    tokens : felt*,
):
    if amounts_index == amounts_len:
        return ()
    end

    IERC20.transfer(
        contract_address=tokens[amounts_index],
        recipient=whitelisted_user,
        amount=amounts[amounts_index],
    )

    _distribute_amounts(
        amounts_index=amounts_index + 1,
        amounts_len=amounts_len,
        amounts=amounts,
        whitelisted_user=whitelisted_user,
        tokens=tokens,
    )
    return ()
end
