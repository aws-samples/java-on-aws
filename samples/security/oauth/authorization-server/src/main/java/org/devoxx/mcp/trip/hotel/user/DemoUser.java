package org.devoxx.mcp.trip.hotel.user;

import org.springframework.security.core.CredentialsContainer;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.AuthorityUtils;
import org.springframework.security.core.userdetails.UserDetails;

import java.io.Serializable;
import java.util.Collection;
import java.util.Objects;

public class DemoUser implements UserDetails, CredentialsContainer, Serializable {

	private final String username;

	private String password;

	private final String email;

	public DemoUser(String username, String password, String email) {
		this.email = email;
		this.password = password;
		this.username = username;
	}

	DemoUser(DemoUser other) {
		this.username = other.getUsername();
		this.password = other.getPassword().replace("{noop}", "");
		this.email = other.getUserEmail();
	}

	@Override
	public Collection<? extends GrantedAuthority> getAuthorities() {
		return AuthorityUtils.NO_AUTHORITIES;
	}

	@Override
	public String getPassword() {
		return "{noop}" + this.password;
	}

	@Override
	public String getUsername() {
		return this.username;
	}

	@Override
	public void eraseCredentials() {
		this.password = null;
	}

	public String getUserEmail() {
		return this.email;
	}

	@Override
	public boolean equals(Object o) {
		if (o == null || getClass() != o.getClass())
			return false;

		DemoUser user = (DemoUser) o;
		return Objects.equals(username, user.username) && Objects.equals(password, user.password)
				&& Objects.equals(email, user.email);
	}

	@Override
	public int hashCode() {
		int result = Objects.hashCode(username);
		result = 31 * result + Objects.hashCode(password);
		result = 31 * result + Objects.hashCode(email);
		return result;
	}

	@Override
	public String toString() {
		return "DemoUser{" + "username='" + username + "'" + ", email=" + email + "}";
	}

}
