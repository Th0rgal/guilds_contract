%lang starknet

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_le, assert_lt
from starkware.starknet.common.syscalls import call_contract, get_caller_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub

from contracts.utils.constants import FALSE, TRUE

from openzeppelin.token.erc721.library import (
    ERC721_name,
    ERC721_symbol,
    ERC721_balanceOf,
    ERC721_ownerOf,
    ERC721_getApproved,
    ERC721_isApprovedForAll,
    ERC721_tokenURI,
    ERC721_initializer,
    ERC721_approve,
    ERC721_setApprovalForAll,
    ERC721_transferFrom,
    ERC721_safeTransferFrom,
    ERC721_mint,
    ERC721_burn,
    ERC721_only_token_owner,
    ERC721_setTokenURI,
)

from openzeppelin.introspection.ERC165 import ERC165_supports_interface

from openzeppelin.access.ownable import (
    Ownable_initializer,
    Ownable_only_owner,
    Ownable_transfer_ownership,
)

#
# Structs
#

struct CertificateData:
    member token_id : Uint256
    member share : Uint256
    member owner : felt
    member guild : felt
end

#
# Storage variables
#

@storage_var
func _certificate_id(owner : felt) -> (token_id : Uint256):
end

@storage_var
func _certificate_data(token_id : Uint256) -> (res : CertificateData):
end

@storage_var
func _certificate_data_field(token_id : Uint256, field : felt) -> (res : felt):
end

@storage_var
func _share(token_id : Uint256) -> (res : Uint256):
end

@storage_var
func _total_shares() -> (res : Uint256):
end

@storage_var
func _user_guilds(player : felt, index : felt) -> (guild_contract : felt):
end

@storage_var
func _user_guilds_len(user : felt) -> (size : felt):
end

func _get_user_guilds{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user : felt, guild_index : felt, guilds_len : felt, guilds : felt*
):
    if guild_index == guilds_len:
        return ()
    end

    let (guild_contract) = _user_guilds.read(user, guild_index)
    assert guilds[guild_index] = guild_contract

    _get_user_guilds(user, guild_index + 1, guilds_len, guilds)
    return ()
end

@view
func get_user_guilds{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user : felt
) -> (guilds_len : felt, guilds : felt*):
    alloc_locals
    let (guilds) = alloc()
    let (guilds_len) = _user_guilds_len.read(user)
    if guilds_len == 0:
        return (guilds_len, guilds)
    end

    # Recursively add colonies id from storage to the colonies array
    _get_user_guilds(user, 0, guilds_len, guilds)
    return (guilds_len, guilds)
end

func add_guild_to_user{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user : felt, guild : felt
) -> ():
    let (id) = _user_guilds_len.read(user)
    _user_guilds_len.write(user, id + 1)
    _user_guilds.write(user, id, guild)
    return ()
end

#
# Getters
#

@view
func supportsInterface{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    interfaceId : felt
) -> (success : felt):
    let (success) = ERC165_supports_interface(interfaceId)
    return (success)
end

@view
func name{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (name : felt):
    let (name) = ERC721_name()
    return (name)
end

@view
func symbol{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (symbol : felt):
    let (symbol) = ERC721_symbol()
    return (symbol)
end

@view
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt) -> (
    balance : Uint256
):
    let (balance : Uint256) = ERC721_balanceOf(owner)
    return (balance)
end

@view
func ownerOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokenId : Uint256
) -> (owner : felt):
    let (owner : felt) = ERC721_ownerOf(tokenId)
    return (owner)
end

@view
func getApproved{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokenId : Uint256
) -> (approved : felt):
    let (approved : felt) = ERC721_getApproved(tokenId)
    return (approved)
end

@view
func isApprovedForAll{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, operator : felt
) -> (isApproved : felt):
    let (isApproved : felt) = ERC721_isApprovedForAll(owner, operator)
    return (isApproved)
end

@view
func tokenURI{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokenId : Uint256
) -> (tokenURI : felt):
    let (tokenURI : felt) = ERC721_tokenURI(tokenId)
    return (tokenURI)
end

@view
func get_certificate_id{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt
) -> (token_id : Uint256):
    let (value) = _certificate_id.read(owner)
    return (value)
end

@view
func get_certificate_data{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    token_id : Uint256
) -> (certificate_data : CertificateData):
    let (certificate_data) = _certificate_data.read(token_id)
    return (certificate_data)
end

@view
func get_certificate_data_field{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt,
    field : felt
) -> (
    data : felt
):
    let (token_id) = _certificate_id.read(owner)
    let (data) = _certificate_data_field.read(token_id, field)
    return (data)
end

@view
func get_shares{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt
) -> (share : Uint256):
    let (token_id) = _certificate_id.read(owner)
    let (share) = _share.read(token_id)
    return (share)
end

@view
func get_total_shares{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    total_shares : Uint256
):
    let (total_shares) = _total_shares.read()
    return (total_shares)
end

#
# Constructor
#
@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    name : felt, symbol : felt, owner : felt
):
    ERC721_initializer(name, symbol)
    Ownable_initializer(owner)
    return ()
end

#
# External
#

@external
func approve{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
    to : felt, tokenId : Uint256
):
    ERC721_approve(to, tokenId)
    return ()
end

@external
func setApprovalForAll{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    operator : felt, approved : felt
):
    ERC721_setApprovalForAll(operator, approved)
    return ()
end

@external
func transferFrom{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
    from_ : felt, to : felt, tokenId : Uint256
):
    ERC721_transferFrom(from_, to, tokenId)
    return ()
end

@external
func safeTransferFrom{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
    from_ : felt, to : felt, tokenId : Uint256, data_len : felt, data : felt*
):
    ERC721_safeTransferFrom(from_, to, tokenId, data_len, data)
    return ()
end

@external
func setTokenURI{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
    tokenId : Uint256, tokenURI : felt
):
    Ownable_only_owner()
    ERC721_setTokenURI(tokenId, tokenURI)
    return ()
end

@external
func transfer_ownership{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_owner : felt
):
    Ownable_transfer_ownership(new_owner)
    return ()
end

func _write_certificate_data_field{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    field_len: felt,
    field: felt*,
    values_len: felt,
    values: felt*,
    token_id: Uint256,
    ):
    
    if field_len == 0:
        return ()
    end

    _certificate_data_field.write(token_id, [field], [values])

    _write_certificate_data_field(
        field_len=field_len-1,
        field=field + 1,
        values_len=values_len-1,
        values=values + 1,
        token_id=token_id,

    )
    return ()
end

@external
func mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    guild : felt,
    owner : felt,
    share : Uint256,
    field_len : felt,
    field : felt*,
    values_len : felt,
    values : felt* 
):
    alloc_locals
    
    with_attr error_message("SW Error: field and values length must be the same"):
        assert field_len = values_len
    end

    # todo check guild is caller
    let (certificate_id) = _certificate_id.read(owner)
    let (new_certificate_id, _) = uint256_add(certificate_id, Uint256(1, 0))
    let data = CertificateData(token_id=new_certificate_id, share=share, owner=owner, guild=guild)
    _certificate_id.write(owner, new_certificate_id)
    _certificate_data.write(new_certificate_id, data)
    _write_certificate_data_field(field_len, field, values_len, values, new_certificate_id)
    _share.write(new_certificate_id, share)
    let (current_total_shares) = _total_shares.read()
    let (new_total_shares, _) = uint256_add(current_total_shares, share)
    _total_shares.write(new_total_shares)
    ERC721_mint(owner, new_certificate_id)
    return ()
end

@external
func burn{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt):
    Ownable_only_owner()
    let (token_id) = _certificate_id.read(owner)
    let (current_shares) = _share.read(token_id)
    _share.write(token_id, Uint256(0, 0))
    let (current_total_shares) = _total_shares.read()
    let (new_total_shares) = uint256_sub(current_total_shares, current_shares)
    _total_shares.write(new_total_shares)
    ERC721_burn(token_id)
    return ()
end

@external
func increase_shares{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, amount : Uint256
):
    Ownable_only_owner()
    let (current_shares) = get_shares(owner)
    let (new_share, _) = uint256_add(current_shares, amount)
    let (certificate_id) = _certificate_id.read(owner)
    _share.write(certificate_id, new_share)
    let (current_total_shares) = _total_shares.read()
    let (new_total_shares, _) = uint256_add(current_total_shares, amount)
    _total_shares.write(new_total_shares)
    return ()
end

@external
func decrease_shares{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, amount : Uint256
):
    Ownable_only_owner()
    let (current_shares) = get_shares(owner)
    let (new_share) = uint256_sub(current_shares, amount)
    let (certificate_id) = _certificate_id.read(owner)
    _share.write(certificate_id, new_share)
    let (current_total_shares) = _total_shares.read()
    let (new_total_shares) = uint256_sub(current_total_shares, amount)
    _total_shares.write(new_total_shares)
    return ()
end
